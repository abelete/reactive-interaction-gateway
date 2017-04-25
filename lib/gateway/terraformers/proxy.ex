defmodule Gateway.Terraformers.Proxy do
  @moduledoc """
  Provides middleware proxy for incoming REST requests at specific routes.
  """
  use Plug.Router
  import Joken
  alias Gateway.Clients.Proxy
  alias Gateway.Utils.Jwt

  plug :match
  plug :dispatch

  match _ do
    %{method: method, request_path: request_path} = conn
    # Load proxy config and get list of routes
    # Config can't be located inside /config to be able to use it on runtime
    routes = Poison.decode!(File.read!("priv/proxy/proxy.json"))
    # Find match of request path in proxy routes
    service = Enum.find(routes, fn(route) ->
      match_path(route, request_path) && match_http_method(route, method)
    end)
    # Authenticate request if needed
    authenticate_request(service, conn)
  end

  # Match route path against requested path
  @spec match_path(map, String.t) :: boolean
  defp match_path(route, request_path) do
    # Replace wildcards with regex words
    replace_wildcards = String.replace(route["path"], "{id}", "\\w*")
    # Match requested path against regex
    String.match?(request_path, ~r/#{replace_wildcards}$/)
  end

  # Match route method against requested method
  @spec match_http_method(map, String.t) :: boolean
  defp match_http_method(route, method), do: route["method"] == method

  # Encode custom error messages with Poison to JSON format
  @type json_message :: %{message: String.t}
  @spec encode_error_message(String.t) :: json_message
  defp encode_error_message(message) do
    Poison.encode!(%{message: message})
  end

  # Handle unsupported route
  @spec authenticate_request(nil, map) :: map
  defp authenticate_request(nil, conn) do
    send_resp(conn, 404, encode_error_message("Route is not available"))
  end
  # Check route authentication and forward
  @spec authenticate_request(map, map) :: map
  defp authenticate_request(service, conn) do
    case service["auth"] do
      true -> process_authentication(service, conn)
      false -> forward_request(service, conn)
    end
  end

  @spec process_authentication(String.t, map) :: map
  defp process_authentication(service, conn) do
    # Get request headers
    %{req_headers: req_headers} = conn
    # Search for authorization token
    jwt = Enum.find(req_headers, fn(item) -> elem(item, 0) == "authorization" end)
    case authenticated?(jwt) do
      true -> forward_request(service, conn)
      false -> send_resp(conn, 401, encode_error_message("Missing token"))
    end
  end

  # Authentication failed if JWT in not provided
  @spec authenticated?(nil) :: false
  defp authenticated?(nil), do: false
  # Verify JWT
  @spec authenticated?(tuple) :: boolean
  defp authenticated?(jwt) do
    # Get value for JWT from tuple
    jwt_value = elem(jwt, 1)
    Jwt.valid?(jwt_value)
  end

  @spec forward_request(map, map) :: map
  defp forward_request(service, conn) do
    %{
      method: method,
      request_path: request_path,
      params: params,
      req_headers: req_headers
    } = conn
    # Build URL
    url = build_url(service, request_path)
    # Match URL against HTTP method to forward it to specific service
    res =
      case method do
        "GET" -> Proxy.get!(url, req_headers, [params: Map.to_list(params)])
        "POST" -> Proxy.post!(url, Poison.encode!(params), req_headers)
        "PUT" -> Proxy.put!(url, Poison.encode!(params), req_headers)
        "DELETE" -> Proxy.delete!(url, Poison.encode!(params), req_headers)
        _ -> nil
      end

    send_response({:ok, conn, res})
  end

  # Builds URL where REST request should be proxied
  @spec build_url(map, String.t) :: String.t
  defp build_url(service, request_path) do
    host = System.get_env(service["host"]) || "localhost"
    "#{host}:#{service["port"]}#{request_path}"
  end

  # Function for sending response back to client
  @spec send_response({:ok, map, nil}) :: map
  defp send_response({:ok, conn, nil}) do
    send_resp(conn, 405, encode_error_message("Method is not supported"))
  end
  @spec send_response({:ok, map, map}) :: map
  defp send_response({:ok, conn, %{headers: headers, status_code: status_code, body: body}}) do
    conn = %{conn | resp_headers: headers}
    send_resp(conn, status_code, body)
  end

end