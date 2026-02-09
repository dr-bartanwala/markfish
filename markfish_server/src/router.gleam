import gleam/http
import gleam/io

import wisp.{type Request, type Response}

pub fn route(req: Request) -> Response {
  io.println(req.path)
  case req.method, req.path {
    http.Get, "/home" -> {
      wisp.ok()
      |> wisp.string_body("Home")
    }
    http.Get, "/Page" -> {
      todo
    }
    _, _ -> wisp.ok() |> wisp.string_body("Hello")
  }
}
