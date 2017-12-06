# HPDF

Headless PDF printing (with Chrome)

Use Chrome in Headless mode to print pages to PDF.
Each page is loaded in it's own browser context, similar to an Incognito window.

Pages may be printed that require authentication allowing you to print pages that are behind login wall.

When using HPDF you need to have a headless chrome running.
You can get a headless chrome browser by using a docker container.
A public container can be found at: https://hub.docker.com/r/justinribeiro/chrome-headless/

By default HPDF will look for chrome at `http://localhost:9222`.
This can be configured in your configuration files by using:

```elixir
config :hpdf, HPDF,
  address: "http://my_custom_domain:9222"
```

```sh
docker run -d -p 9222:9222 --cap-add=SYS_ADMIN justinribeiro/chrome-headless
```

### Example

```elixir
case HPDF.print_pdf!(my_url, timeout: 30_000) do
  {:ok, pdf_data} -> do_stuff_with_the_pdf_binary_data(pdf_data)
  {:error, error_type, reason} -> #Handle error
  {:error, reason} -> # Handle error
```

Common error types provided by HPDF
* `:page_error` - An error was returned by the browser
* `:page_redirected` - The URL was redirected
* `:page_load_failure` - The page loaded with a non 200 status code
* `:crashed` - The browser crashed

### Using header authentication

When printing a page using header authentication,
usually it's not only the original page, but all AJAX requests made within it that need to have the authentication header included.

Assuming you have a token

```elixir
header_value = get_my_auth_header()
headers = %{"authorization" => header_value}

case HPDF.print_pdf!(my_url, timeout: 30_000, page_headers: headers) do
  {:ok, pdf_data} -> do_stuff_with_the_pdf_binary_data(pdf_data)
  {:error, error_type, reason} -> #Handle error
  {:error, reason} -> # Handle error
end
```

### Using cookie authentication
An initiating cookie can be used to access pages.

```elixir
cookie = %{
  name: "_cookie_name",
  value: cookie_value,
  domain: "your.domain",
  path: "/",
  secure: true,
  httpOnly: true,
}

{:ok, data} = HPDF.print_pdf!(url, timeout: 30_000, cookie: cookie)
```

### Calling `print_pdf!`

Prints a PDF file with the provided options.
The HPDF.Application must be running before calling this function

### Options

* `timeout` - The timeout for the call. Default 5_000
* `after_load_delay` - The time to wait after the page finishes loading. Allowing for dynamic JS calls and rendering.
* `cookie` - Supply a cookie for the page to be loaded with. See https://chromedevtools.github.io/devtools-protocol/tot/Network/#method-setCookie
* `page_headers` - A map of headers to supply to the page
* `include_headers_on_same_domain` - A bool. Default True. If true, all requests to the same domain will include the same headers as the main page
* `print_options` - A map of options to the print method. See https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-printToPDF
* `max_wait_time` - A time in miliseconds after which the page will be forcefully printed even if there are outstanding requests

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `hpdf` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:hpdf, "~> 0.3.1"}]
end

def application do
  # Specify extra applications you'll use from Erlang/Elixir
  [extra_applications: [:hpdf],
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/hpdf](https://hexdocs.pm/hpdf).
