import envoy
import gleam/erlang/process
import gleam/io
import gleam/result
import mist
import mork
import mork/document
import router.{route}
import simplifile
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()
  let secret = "secret key"
  let assert Ok(_) =
    wisp_mist.handler(route, secret)
    |> mist.new
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}
