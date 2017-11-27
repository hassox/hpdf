defmodule HPDF.Printer do
  @moduledoc false

  # This module listens to a web socket that has been opened to a chrome context.
  # Implemeted in web_socket.ex
  # When `print_page!` is called, it navigates to the provided URL with network interception turned on
  #
  # It then watches each request and response, replacing headers on intercepted requests
  # and tracking responses.
  #
  # Once a `Page.frameStoppedLoading` event has been received the page has mostly stopped loading.
  # This might be true and some time `after_load_delay` is provided to allow any JS scripts to load dynamically.
  # Each time a request is made after the page is "loaded", the timer is reset once the response is received.

  use HPDF.WebSocket

  require Logger

  @pdf_req_id 42
  @default_timeout 5_000

  # setting a cookie. The cookie value should describe
  # the values provided in
  # https://chromedevtools.github.io/devtools-protocol/tot/Network/#method-setCookie
  defstruct socket: nil, # The web socket to use. This is given by the starting process.
            receiver: nil, # The receiver process. This is given by the starting process.
            after_load_delay: 750, # How long to wait after the page is loaded before starting to print
            cookie: nil, # The cookie options https://chromedevtools.github.io/devtools-protocol/tot/Network/#method-setCookie
            active_requests: 0, # A counter of the active requests that are in-progress (not including web-sockets)
            page_url: nil, # The URL of the page to print
            page_loaded?: false,
            page_headers: nil, # Page headers will be included on the initial page load
            include_headers_on_same_domain: true, # if set to true, any headers that were given for the original page will also be used on requests on the same domain
            timer: nil, # private
            reply_to: nil, # private
            print_options: %{}, # options for printing https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-printToPDF
            page_frame: nil # an id that chrome is using for the frame


  @doc false
  def init(args) do
    {:ok, init_state} = super(args)

    afd = Keyword.get(args, :after_load_delay, 750)
    headers = Keyword.get(args, :page_headers)
    cookie = Keyword.get(args, :cookie)
    print_options = Keyword.get(args, :print_options, %{})
    headers =
      if headers do
        for {k, v} <- headers, into: %{}, do: {to_string(k), v}
      end

    on_same_domain = Keyword.get(args, :include_headers_on_same_domain, true)

    state =
      %__MODULE__{
        receiver: init_state.receiver,
        socket: init_state.socket,
        after_load_delay: afd,
        page_headers: headers,
        include_headers_on_same_domain: on_same_domain,
        cookie: cookie,
        print_options: print_options,
        page_frame: nil
      }

    {:ok, state}
  end

  @doc false
  def print_page!(ws_address, url, opts \\ []) do
    ws_uri = URI.parse(ws_address)

    args = Keyword.merge(
      [
        socket_args: [{ws_uri.host, ws_uri.port}, [path: ws_uri.path]],
      ],
      opts
    )

    {:ok, printer} = __MODULE__.start_link(args)
    print_page(printer, url, opts)
  end

  defp print_page(printer, url, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(printer, {:print_pdf, url, opts}, timeout)
  end

  def handle_connect(state) do
    Logger.debug("HPDF Printer Connected")
    {:noreply, state}
  end

  def handle_call({:print_pdf, url, _opts}, from, state) do
    method(state.socket, "Page.enable", %{}, 1)
    method(state.socket, "Network.enable", %{}, 2)
    method(state.socket, "Network.setRequestInterceptionEnabled", %{enabled: true}, 5)

    if state.cookie do
      method(state.socket, "Network.setCookie", state.cookie, 8)
    end

    method(state.socket, "Page.navigate", %{url: url}, 3)

    {:noreply, %{state | reply_to: from, page_url: url}}
  end

  def handle_frame({:text, %{"id" => @pdf_req_id, "result" => %{ "data" => pdf_data}}}, state) do
    handle_pdf(pdf_data, state)
    {:stop, :normal, state}
  end

  def handle_frame({:text, %{"error" => %{"message" => msg}}}, state) do
    GenServer.reply(state.reply_to, {:error, :page_error, msg})
    {:stop, :normal, state}
  end

  def handle_frame({:text, %{"id" => 3, "result" => %{"frameId" => frameId}}}, state) do
    {:noreply, %{state | page_frame: frameId}}
  end

  def handle_frame(
    {:text,
    %{"method" => "Network.requestWillBeSent",
      "params" => %{"frameId" => frameId, "redirectResponse" => %{}, "request" => %{"url" => redirectURL}},
    }}, state)
  do
    if frameId == state.page_frame do
      GenServer.reply(state.reply_to, {:error, :page_redirected, redirectURL})
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_frame(
    {:text,
    %{
      "method" => "Network.responseReceived",
      "params" => %{"response" => %{"status" => status, "url" => url}}
    }} = frame,
    %{page_url: url} = state
  ) when not (status in (200..299)) do
    Logger.debug("not a 200: #{inspect(frame)}")
    GenServer.reply(state.reply_to, {:error, :page_load_failure, status})
    {:stop, :normal, state}
  end

  def handle_frame(
    {:text, %{"method" => "Network.requestWillBeSent"}} = frame,
    %{timer: timer, active_requests: count} = state
  ) do
    Logger.debug(inspect(frame))
    if timer do
      Logger.debug("Cancelling HPDF printer timer #{count}")
      Process.cancel_timer(timer)
    end
    {:noreply, %{state | active_requests: state.active_requests + 1, timer: nil}}
  end

  def handle_frame(
    {:text, %{"method" => "Network.responseReceived"}} = frame,
    %{timer: timer, active_requests: count} = state
  ) do
    Logger.debug("FRAME: #{inspect(frame)}")
    if timer do
      Logger.debug("Canceling HPDF printer timer #{count}")
      Process.cancel_timer(timer)
    end

    Logger.debug("Maybe start the timer? #{inspect(state.page_loaded?)} #{count}")
    new_timer =
      if state.page_loaded? && count <= 1 do
        Logger.debug("Restarting HPDF printer timer")
        Process.send_after(self(), {:print_page}, state.after_load_delay)
      end

    {:noreply, %{state | active_requests: count - 1, timer: new_timer}}
  end

  def handle_frame(
    {:text,
    %{
      "method" => "Network.requestIntercepted",
      "params" => %{
        "interceptionId" => interception_id,
        "request" => request,
      }
    }},
    state
  )  do
    updated_headers = updated_headers_for_request(request, state)
    method(
      state.socket,
      "Network.continueInterceptedRequest",
      %{"headers" => updated_headers, "interceptionId" => interception_id},
      67
    )
    {:noreply, state}
  end

  def handle_frame({:text, %{"method" => "Page.frameStoppedLoading"}} = frame, state) do
    Logger.debug("STOPPED LOADING #{inspect(frame)}")
    Logger.debug("HPDF Page downloaded - Starting the timer #{state.after_load_delay} (#{state.active_requests})")
    timer =
      if state.active_requests <= 1 do
        Process.send_after(self(), {:print_page}, state.after_load_delay)
      end
    {:noreply, %{state | page_loaded?: true, timer: timer}}
  end

  def handle_frame({:text, %{"method" => "Inspector.targetCrashed"}} = frame, state) do
    Logger.debug("Inspector crashed: #{inspect(frame)}")
    GenServer.reply(state.reply_to, {:error, :crashed, :crashed})
    {:stop, :abnormal, state}
  end

  def handle_frame(frame, state) do
    Logger.debug("HPDF: Unknown Frame: #{inspect(frame)}")
    {:noreply, state}
  end

  def handle_info({:print_page}, state) do
    Logger.debug("HPDF printing the PDF")
    method(state.socket, "Page.printToPDF", state.print_options, @pdf_req_id)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unknown state #{inspect msg}", state)
    {:noreply, state}
  end

  def handle_error(reason, state) do
    Logger.debug("HPDF Error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_close(reason, state) do
    Logger.warn("HPDF printer close #{inspect(reason)}")
    {:noreply, state}
  end

  def terminate(_reason, state) do
    Process.exit(state.receiver, :kill)
    :ok
  end

  defp handle_pdf(pdf_data, state) do
    data = Base.decode64(pdf_data)
    case data do
      {:ok, bytes} ->
        GenServer.reply(state.reply_to, {:ok, bytes})
      {:error, reason} ->
        GenServer.reply(state.reply_to, {:error, reason})
    end
  end

  defp method(socket, meth, params, nil) do
    method(socket, meth, params, 56)
  end

  defp method(socket, meth, params, id) do
    args = %{method: meth, id: id, params: params}
    Socket.Web.send(socket, {:text, Poison.encode!(args)})
  end

  defp updated_headers_for_request(
    %{"headers" => headers},
    %{page_headers: nil}
  ) do
    headers
  end

  defp updated_headers_for_request(
    %{"headers" => req_headers, "url" => req_url},
    %{page_headers: headers, page_url: url, include_headers_on_same_domain: true}
  ) when is_map(headers) do
    uri = URI.parse(url)
    req_uri = URI.parse(req_url)

    if uri.host == req_uri.host do
      Map.merge(req_headers, headers)
    else
      req_headers
    end
  end

  defp updated_headers_for_request(%{"headers" => req_headers}, _) do
    req_headers
  end
end
