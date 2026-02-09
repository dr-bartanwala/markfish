import file_streams/file_stream
import gleam/int
import gleam/list
import gleam/result
import gleam/string

const fnv_prime = 1_099_511_628_211

const fnv_offset_basis = 14_695_981_039_346_656_037

const fnv_mask_64 = 0xffffffffffffffff

pub type Chunk {
  Chunk(chunk_hash: Int, chunk_data: String)
}

pub fn chunkify(stream) -> List(Chunk) {
  chunkify_loop(stream, [], False)
}

type ChunkType {
  New
  Paragraph
  Quote
  Code1
  Code2
  List
}

type LineStyle {
  None
  EmptyLine
  ParagraphLine
  QuoteLine
  Code1Line
  Code1OnlyLine
  Code2Line
  Code2OnlyLine
  HeadingLine
  ListLine
  ThematicBreakLine
}

type ExitType {
  Continue
  ExitInclude
  ExitSkip
}

fn is_thematic_break(line: String, char: String, count: Int) -> Bool {
  case line |> string.pop_grapheme, char {
    Ok(#(c, rest)), _ if c == " " || c == "\n" || c == "\r\n" ->
      is_thematic_break(rest, char, count)
    Error(Nil), _ -> count >= 3
    Ok(#("_", rest)), "" -> is_thematic_break(rest, "_", 1)
    Ok(#("-", rest)), "" -> is_thematic_break(rest, "-", 1)
    Ok(#("*", rest)), "" -> is_thematic_break(rest, "*", 1)
    Ok(#(c, rest)), _ if c == char -> is_thematic_break(rest, char, count + 1)
    _, _ -> False
  }
}

fn is_list_prefix(line: String, set: Bool) -> Bool {
  case string.pop_grapheme(line) {
    Error(_) -> False
    Ok(#(c, rest)) ->
      case c, set {
        "-", _ -> string.starts_with(rest, " ")
        _, False ->
          case int.parse(c) {
            Ok(_) -> is_list_prefix(rest, True)
            Error(_) -> False
          }
        ".", True -> string.starts_with(rest, " ")
        _, _ -> False
      }
  }
}

fn determine_line_style(line: String) -> LineStyle {
  case line {
    " " <> rest -> determine_line_style(rest)
    "\n" | "\r\n" -> EmptyLine
    "" -> EmptyLine
    ">" <> _ -> QuoteLine
    "```\n" -> Code1OnlyLine
    "~~~\n" -> Code2OnlyLine
    "```" <> _ -> Code1Line
    "~~~" <> _ -> Code2Line
    "#" <> _ -> HeadingLine
    _ -> {
      case is_thematic_break(line, "", 0) {
        True -> ThematicBreakLine
        False -> {
          case is_list_prefix(line, False) {
            True -> ListLine
            False -> ParagraphLine
          }
        }
      }
    }
  }
}

fn determine_new_chunk_type(line_style: LineStyle) -> ChunkType {
  case line_style {
    EmptyLine -> New
    QuoteLine -> Quote
    Code1Line -> Code1
    Code1OnlyLine -> Code1
    Code2Line -> Code2
    Code2OnlyLine -> Code2
    ListLine -> List
    _ -> Paragraph
  }
}

fn should_exit_chunk(chunk_type, line_style, prev_line) -> ExitType {
  case chunk_type, line_style, prev_line {
    New, _, _ -> Continue
    Code1, Code1OnlyLine, _ -> ExitInclude
    Code1, _, _ -> Continue
    Code2, Code2OnlyLine, _ -> ExitInclude
    Code2, _, _ -> Continue
    List, ThematicBreakLine, _ -> ExitInclude
    List, HeadingLine, _ -> ExitInclude
    List, current, EmptyLine if current != ListLine -> ExitSkip
    List, _, _ -> Continue
    Quote, EmptyLine, _ -> ExitInclude
    Quote, ThematicBreakLine, _ -> ExitInclude
    Quote, _, _ -> Continue
    Paragraph, ParagraphLine, prev if prev != HeadingLine -> Continue
    Paragraph, HeadingLine, HeadingLine -> Continue
    Paragraph, HeadingLine, _ -> ExitInclude
    Paragraph, ThematicBreakLine, _ -> ExitInclude
    Paragraph, EmptyLine, _ -> ExitInclude
    Paragraph, _, _ -> ExitSkip
  }
}

fn perform_running_hash(running_hash: Int, line: String) -> Int {
  case string.pop_grapheme(line) {
    Ok(#(char, rest)) ->
      char
      |> string.to_utf_codepoints
      |> list.first
      |> result.map(fn(unicode) {
        unicode
        |> string.utf_codepoint_to_int
        |> int.bitwise_exclusive_or(
          running_hash * fnv_prime |> int.bitwise_and(fnv_mask_64),
        )
      })
      |> result.unwrap(running_hash)
      |> perform_running_hash(rest)

    Error(_) -> running_hash
  }
}

fn parse_chunk_loop(
  stream,
  running_hash: Int,
  current_chunk_type: ChunkType,
  previous_line_style: LineStyle,
  current_chunk_data: String,
) -> #(Chunk, Bool) {
  case file_stream.read_line(stream) {
    Error(_) -> #(Chunk(running_hash, current_chunk_data), True)

    Ok(line) -> {
      let line_style = determine_line_style(line)
      let new_chunk_type = case current_chunk_type {
        New -> determine_new_chunk_type(line_style)
        _ -> current_chunk_type
      }

      case
        should_exit_chunk(current_chunk_type, line_style, previous_line_style)
      {
        Continue ->
          parse_chunk_loop(
            stream,
            perform_running_hash(running_hash, line),
            new_chunk_type,
            line_style,
            current_chunk_data <> line,
          )
        ExitInclude -> #(
          Chunk(
            perform_running_hash(running_hash, line),
            current_chunk_data <> line,
          ),
          False,
        )
        ExitSkip -> #(Chunk(running_hash, current_chunk_data), False)
      }
    }
  }
}

pub fn parse_chunk(stream) -> #(Chunk, Bool) {
  parse_chunk_loop(stream, fnv_offset_basis, New, None, "")
}

fn chunkify_loop(stream, chunks: List(Chunk), break: Bool) -> List(Chunk) {
  case break {
    True -> chunks |> list.reverse
    False ->
      parse_chunk(stream)
      |> fn(tuple) -> List(Chunk) {
        chunkify_loop(stream, [tuple.0, ..chunks], tuple.1)
      }
  }
}
