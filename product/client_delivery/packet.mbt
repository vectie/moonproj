///|
/// Editable customer-facing text, separate from the captured result body.
pub(all) struct Note {
  title : String
  summary : String
  review_request : String
  filename : String
} derive(Debug, Eq)

///|
pub suberror InvalidPacket {
  Invalid(String)
} derive(Debug)

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
/// Validate captured text integrity. This does not authenticate its origin or
/// customer acceptance. The caller must separately bind the source to its task.
pub fn body(source : String) -> Bytes raise InvalidPacket {
  if source.length() > 524288 || @utf8.encode(source).length() > 524288 {
    raise Invalid("来源文件过大")
  }
  let value = @json.parse(source) catch {
    _ => raise Invalid("来源文件无法读取")
  }
  if text(value, "contract_version") != "moonproj.accepted-human-result.v1" ||
    text(value, "source_product") != "moonproj" ||
    text(value, "provenance_scope") != "captured_accepted_human_revision" ||
    text(value, "authenticity") != "unsigned_source_observation" ||
    field(value, "authorizing") != Json::boolean(false) {
    raise Invalid("仅支持已接受人工修订的文本来源")
  }
  let content = field(value, "content")
  let encoded = text(content, "data")
  if text(content, "encoding") != "base64" ||
    text(content, "media_type") != "text/plain;charset=utf-8" ||
    !(field(content, "data") is String(_)) {
    raise Invalid("结果必须是捕获的 UTF-8 文本")
  }
  let bytes = @base64.decode(encoded) catch {
    _ => raise Invalid("结果编码无效")
  }
  if bytes.length() > 262144 ||
    field(content, "size_bytes") != Json::number(bytes.length().to_double()) ||
    @base64.encode(bytes) != encoded ||
    text(content, "sha256") !=
    "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes)) ||
    bytes.iter().any(byte => byte == 0) {
    raise Invalid("结果字节与已捕获来源不一致")
  }
  let decoded = @utf8.decode(bytes) catch {
    _ => raise Invalid("结果不是有效 UTF-8 文本")
  }
  if @utf8.encode(decoded) != bytes {
    raise Invalid("结果无法无损保留")
  }
  bytes
}

///|
pub fn body_text(source : String) -> String raise InvalidPacket {
  let bytes = body(source)
  @utf8.decode(bytes) catch {
    _ => raise Invalid("结果不是有效 UTF-8 文本")
  }
}

///|
/// A portable basename only. The two packet-owned filenames are reserved.
pub fn filename_valid(name : String) -> Bool {
  if name.is_empty() ||
    name.trim().to_owned() != name ||
    @utf8.encode(name).length() > 128 ||
    name == "." ||
    name == ".." ||
    name.has_suffix(".") ||
    name
    .iter()
    .any(c => {
      c.to_int() < 32 ||
      c.to_int() == 127 ||
      "/\\:*?\"<>|".contains(c.to_string())
    }) {
    return false
  }
  let lower = name.to_lower()
  if ["readme.txt", "source-observation.json"].contains(lower) {
    return false
  }
  let stem = lower.split(".").next().unwrap_or("").to_owned()
  ![
    "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
    "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8",
    "lpt9",
  ].contains(stem)
}

///|
pub fn default_filename(path : String) -> String {
  let parts = path
    .replace_all(old="\\", new="/")
    .split("/")
    .map(part => part.to_owned())
    .collect()
  let name = parts.last().unwrap_or("")
  if filename_valid(name) {
    name
  } else {
    "delivered-result.txt"
  }
}

///|
pub fn validate_note(note : Note) -> String {
  if !filename_valid(note.filename) {
    "请使用不含路径的文件名，并避开 README.txt 与 source-observation.json。"
  } else if note.title.trim().is_empty() {
    "请填写交付标题。"
  } else if note.title.length() > 200 ||
    note.summary.length() > 8000 ||
    note.review_request.length() > 8000 {
    "标题最多 200 字；交付说明与审阅请求各最多 8000 字。"
  } else if [note.title, note.summary, note.review_request].any(value => {
      value.contains("\u{0}")
    }) {
    "说明中不能包含空字符。"
  } else {
    ""
  }
}

///|
pub fn readme(note : Note) -> String {
  note.title +
  "\n\n交付文件\n" +
  note.filename +
  "\n\n交付说明\n" +
  note.summary +
  "\n\n请审阅\n" +
  note.review_request +
  "\n"
}

///|
fn crc32(bytes : Bytes) -> UInt {
  let mut crc = 0xffffffffU
  for byte in bytes {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = if (crc & 1U) == 1U { (crc >> 1) ^ 0xedb88320U } else { crc >> 1 }
    }
  }
  crc ^ 0xffffffffU
}

///|
fn short(buffer : @buffer.Buffer, value : Int) -> Unit {
  buffer.write_byte((value & 255).to_byte())
  buffer.write_byte(((value >> 8) & 255).to_byte())
}

///|
// Deterministic ZIP/store entries: no compression dependency or filesystem
// lookup. Payload bytes are copied directly, including BOM and line endings.
fn zip(files : Array[(String, Bytes)]) -> Bytes {
  let output = @buffer.Buffer::Buffer()
  let directory = @buffer.Buffer::Buffer()
  for (name, bytes) in files {
    let name = @utf8.encode(name)
    // Unicode Path extra field also supports extractors that do not honor
    // the language-encoding flag alone for DOS-origin ZIP entries.
    let extra = @buffer.Buffer::Buffer()
    short(extra, 0x7075)
    short(extra, 5 + name.length())
    extra.write_byte(1)
    extra.write_uint_le(crc32(name))
    extra.write_bytes(name)
    let checksum = crc32(bytes)
    let offset = output.length()
    output.write_uint_le(0x04034b50U)
    for value in [20, 2048, 0, 0, 33] {
      short(output, value)
    }
    output.write_uint_le(checksum)
    output.write_int_le(bytes.length())
    output.write_int_le(bytes.length())
    short(output, name.length())
    short(output, extra.length())
    output.write_bytes(name)
    output.write_bytes(extra.to_bytes())
    output.write_bytes(bytes)
    directory.write_uint_le(0x02014b50U)
    for value in [20, 20, 2048, 0, 0, 33] {
      short(directory, value)
    }
    directory.write_uint_le(checksum)
    directory.write_int_le(bytes.length())
    directory.write_int_le(bytes.length())
    short(directory, name.length())
    short(directory, extra.length())
    for _ in 0..<3 {
      short(directory, 0)
    }
    directory.write_int_le(0)
    directory.write_int_le(offset)
    directory.write_bytes(name)
    directory.write_bytes(extra.to_bytes())
  }
  let offset = output.length()
  output.write_bytes(directory.to_bytes())
  output.write_uint_le(0x06054b50U)
  short(output, 0)
  short(output, 0)
  short(output, files.length())
  short(output, files.length())
  output.write_int_le(directory.length())
  output.write_int_le(offset)
  short(output, 0)
  output.to_bytes()
}

///|
/// Build a local delivery packet. No transmission or business transition occurs.
pub fn archive(
  source : String,
  note : Note,
  include_source? : Bool = false,
) -> Bytes raise InvalidPacket {
  let error = validate_note(note)
  if !error.is_empty() {
    raise Invalid(error)
  }
  let files = [
    (note.filename, body(source)),
    ("README.txt", @utf8.encode(readme(note))),
  ]
  if include_source {
    files.push(("source-observation.json", @utf8.encode(source)))
  }
  zip(files)
}
