///|
/// Portable editable task text, not a saved company task or a draft-store backup.
#derive(Debug, Eq)
pub(all) struct Packet {
  title : String
  acceptance : String
  source_reference : String
  observed_problem : String
  begin_date : String
  end_date : String
}

///|
#derive(Debug, Eq)
pub(all) suberror PacketError {
  Invalid(String)
}

///|
fn field(fields : Map[String, Json], key : String) -> String raise PacketError {
  guard fields.get(key) is Some(String(value)) else {
    raise Invalid("工作简报字段必须存在且为文本：" + key)
  }
  if value.length() > 8192 {
    raise Invalid("工作简报字段超过 8192 字符上限：" + key)
  }
  value
}

///|
/// Decode the exact six text fields. Even incomplete dates remain editable text.
/// Structured actor, identity, credentials and execution settings are not accepted.
pub fn decode(text : String) -> Packet raise PacketError {
  if text.length() > 262144 || @utf8.encode(text).length() > 262144 {
    raise Invalid("工作简报超过 256 KiB 读取上限。")
  }
  let value = @json.parse(text) catch {
    _ =>
      raise Invalid("无法解析工作简报 JSON；请检查文件内容。")
  }
  guard value is Object(fields) else {
    raise Invalid("工作简报必须为 JSON 对象。")
  }
  guard fields.get("schema") is Some(String("moonproj.work-brief.v1")) else {
    raise Invalid("请选择 moonproj.work-brief.v1 工作简报。")
  }
  let allowed = [
    "schema", "title", "acceptance", "source_reference", "observed_problem", "begin_date",
    "end_date",
  ]
  for key, _ in fields {
    if !allowed.contains(key) {
      raise Invalid("工作简报不支持字段：" + key)
    }
  }
  {
    title: field(fields, "title"),
    acceptance: field(fields, "acceptance"),
    source_reference: field(fields, "source_reference"),
    observed_problem: field(fields, "observed_problem"),
    begin_date: field(fields, "begin_date"),
    end_date: field(fields, "end_date"),
  }
}

///|
/// Validate and export the same exact editable strings; never trim or infer dates.
pub fn Packet::encode(self : Packet) -> String raise PacketError {
  let value : Json = {
    "schema": "moonproj.work-brief.v1",
    "title": self.title,
    "acceptance": self.acceptance,
    "source_reference": self.source_reference,
    "observed_problem": self.observed_problem,
    "begin_date": self.begin_date,
    "end_date": self.end_date,
  }
  let text = value.stringify()
  ignore(decode(text))
  text
}
