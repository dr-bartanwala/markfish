import envoy
import ewe
import gleam/erlang/process
import gleam/io
import internal/router.{RouterConfig, router}
import internal/stateman.{start_stateman}

pub fn main() -> Nil {
  let dir = "/app/data"
  let assert Ok(user) = envoy.get("USER")
  let assert Ok(pass) = envoy.get("PASS")

  let router_config = RouterConfig(user, pass)

  let state = start_stateman(dir)
  let assert Ok(_) =
    ewe.new(router(_, state, router_config))
    |> ewe.bind("0.0.0.0")
    |> ewe.listening(port: 8000)
    |> ewe.start()
  io.println("Listening on 0.0.0.0:8000")
  process.sleep_forever()
}
