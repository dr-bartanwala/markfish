import envoy
import ewe
import gleam/erlang/process
import gleam/io
import internal/fileman.{start_fileman}
import internal/router.{router}
import internal/state.{start_state}

pub fn main() -> Nil {
  envoy.set("DIR", "D:/Programming/Projects/markfish/markfish_server")
  envoy.set("USER", "default")
  envoy.set("PASS", "default")

  let state = start_state()

  let assert Ok(_) =
    ewe.new(router(_, state))
    |> ewe.bind("0.0.0.0")
    |> ewe.listening(port: 8000)
    |> ewe.start()
  io.println("Listening on 0.0.0.0:8000")
  process.sleep_forever()
}
