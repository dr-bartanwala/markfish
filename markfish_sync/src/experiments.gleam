import gleam/erlang/process
import gleam/io
import internal/scanner.{CommonInfo, Scan, get_scanner}

fn run_test() {
  let base_dir = "D:/Programming/Notes/Notes/Blogs/"
  let server_addr = "http://localhost:8000"

  let scanner =
    get_scanner(CommonInfo(base_dir, "default", "default", server_addr))

  process.send(scanner, Scan)
  process.sleep_forever()
}

pub fn execute() -> Nil {
  run_test()
  io.println("completed")
}
