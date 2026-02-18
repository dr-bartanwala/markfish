import envoy
import gleam/erlang/process
import gleam/io
import internal/scanner.{CommonInfo, Scan, get_scanner}

pub fn main() -> Nil {
  io.println("Hello from markfish_sync!")
  let assert Ok(base_dir) = envoy.get("DIR")
  let assert Ok(server_addr) = envoy.get("SERVER_ADDR")

  let scanner =
    get_scanner(CommonInfo(base_dir, "default", "default", server_addr))

  process.send(scanner, Scan)
  process.sleep_forever()
}
