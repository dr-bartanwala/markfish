import envoy
import gleam/erlang/process
import gleam/io
import internal/scanner.{CommonInfo, Scan, get_scanner}

pub fn main() -> Nil {
  io.println("Hello from markfish_sync!")
  let assert Ok(base_dir) = envoy.get("DIR")
  let assert Ok(server_addr) = envoy.get("SERVER_ADDR")
  let assert Ok(user) = envoy.get("USER")
  let assert Ok(pass) = envoy.get("PASS")

  let scanner = get_scanner(CommonInfo(base_dir, user, pass, server_addr))

  process.send(scanner, Scan)
  process.sleep_forever()
}
