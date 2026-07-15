///|
/// Native, dependency-free XLSX export for report-shaped tabular data.
///
/// The browser ERP exporter uses ExcelJS.  The native service deliberately
/// keeps this boundary small and deterministic: it accepts the same sheet /
/// column / row contract and emits an uncompressed ZIP containing the minimum
/// SpreadsheetML parts required by Excel and common readers.
const XLSX_MAX_SHEETS : Int = 20

///|
const XLSX_MAX_CELLS : Int = 1000000

///|
const XLSX_MAX_CELL_LENGTH : Int = 32768

///|
struct XlsxColumn {
  label : String
  field : String
  width : Double
  kind : String
}

///|
struct XlsxSheet {
  name : String
  columns : Array[XlsxColumn]
  rows : Array[Json]
}

///|
struct XlsxZipEntry {
  name : String
  data : Bytes
  crc : Int64
}

///|
fn xlsx_text(value : Json) -> String {
  match value {
    String(text) => text
    Number(number, ..) => number.to_string()
    True => "true"
    False => "false"
    Null => ""
    _ => value.stringify()
  }
}

///|
fn xlsx_xml_text(value : String) -> String {
  let mut result = ""
  for char in value.iter() {
    // XML 1.0 allows tab/newline/CR and printable Unicode.  Replacing other
    // controls keeps the generated workbook readable instead of malformed.
    let code = char.to_int()
    if code == 9 || code == 10 || code == 13 || code >= 32 {
      result = result +
        (match char {
          '&' => "&amp;"
          '<' => "&lt;"
          '>' => "&gt;"
          '"' => "&quot;"
          '\'' => "&apos;"
          _ => char.to_string()
        })
    } else {
      result = result + " "
    }
  }
  result
}

///|
fn xlsx_json_array(
  value : Json,
  key : String,
) -> Array[Json] raise CompanyServiceError {
  match json_field(value, key) {
    Some(Array(items)) => items
    _ => raise reject(422, key + " must be an array")
  }
}

///|
fn xlsx_safe_sheet_name(value : String, fallback : String) -> String {
  let source = if value.trim().is_empty() {
    fallback
  } else {
    value.trim().to_owned()
  }
  let mut result = ""
  for char in source.iter() {
    if char == '/' ||
      char == '\\' ||
      char == '?' ||
      char == '*' ||
      char == '[' ||
      char == ']' ||
      char == ':' {
      result = result + "_"
    } else {
      result = result + char.to_string()
    }
  }
  let result = if result.is_empty() { fallback } else { result }
  if result.length() > 31 {
    result[:31].to_owned()
  } else {
    result
  }
}

///|
fn xlsx_safe_filename(value : String) -> String {
  let source = if value.trim().is_empty() {
    "export.xlsx"
  } else {
    value.trim().to_owned()
  }
  let mut result = ""
  for char in source.iter() {
    if char == '/' ||
      char == '\\' ||
      char == ':' ||
      char == '*' ||
      char == '?' ||
      char == '"' ||
      char == '<' ||
      char == '>' ||
      char == '|' ||
      char.to_int() < 32 {
      result = result + "_"
    } else {
      result = result + char.to_string()
    }
  }
  let result = if result.is_empty() { "export.xlsx" } else { result }
  let result = if result.length() > 120 {
    result[:120].to_owned()
  } else {
    result
  }
  if result.to_lower().has_suffix(".xlsx") {
    result
  } else {
    result + ".xlsx"
  }
}

///|
fn xlsx_column_letter(index : Int) -> String {
  let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  let mut value = index + 1
  let mut result = ""
  while value > 0 {
    let rem = (value - 1) % 26
    result = alphabet.get_char(rem).unwrap().to_string() + result
    value = (value - 1) / 26
  }
  result
}

///|
fn xlsx_width(value : Json) -> Double {
  match value {
    Number(number, ..) if number >= 4.0 && number <= 80.0 => number
    _ => 14.0
  }
}

///|
fn xlsx_parse_column(
  value : Json,
  _index : Int,
) -> XlsxColumn raise CompanyServiceError {
  match value {
    Object(_) => {
      let field = json_text(value, "field", "").trim().to_owned()
      if field.is_empty() {
        raise reject(422, "column field is required")
      }
      {
        label: json_text(value, "label", field),
        field,
        width: xlsx_width(json_field(value, "width").unwrap_or(Json::null())),
        kind: json_text(value, "type", "text").to_lower(),
      }
    }
    _ => raise reject(422, "sheet columns must contain objects")
  }
}

///|
fn xlsx_parse_sheet(
  value : Json,
  index : Int,
) -> XlsxSheet raise CompanyServiceError {
  match value {
    Object(_) => {
      let raw_columns = xlsx_json_array(value, "columns")
      let columns : Array[XlsxColumn] = []
      for index in 0..<raw_columns.length() {
        columns.push(xlsx_parse_column(raw_columns[index], index))
      }
      let rows = xlsx_json_array(value, "rows")
      {
        name: xlsx_safe_sheet_name(
          json_text(value, "name", "Sheet" + (index + 1).to_string()),
          "Sheet" + (index + 1).to_string(),
        ),
        columns,
        rows,
      }
    }
    _ => raise reject(422, "sheets must contain objects")
  }
}

///|
fn xlsx_cell_value(row : Json, field : String) -> Json {
  match row {
    Object(fields) => fields.get(field).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn xlsx_style(kind : String) -> Int {
  match kind {
    "currency" => 2
    "number" => 3
    "percent" => 4
    "date" => 5
    _ => 0
  }
}

///|
fn xlsx_inline_cell(reference : String, value : String, style : Int) -> String {
  "<c r=\"" +
  reference +
  "\" t=\"inlineStr\"" +
  (if style == 0 { "" } else { " s=\"" + style.to_string() + "\"" }) +
  "><is><t xml:space=\"preserve\">" +
  xlsx_xml_text(value) +
  "</t></is></c>"
}

///|
fn xlsx_number_cell(reference : String, value : String, style : Int) -> String {
  "<c r=\"" +
  reference +
  "\"" +
  (if style == 0 { "" } else { " s=\"" + style.to_string() + "\"" }) +
  "><v>" +
  xlsx_xml_text(value) +
  "</v></c>"
}

///|
fn xlsx_worksheet_xml(sheet : XlsxSheet) -> String {
  let mut xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
    "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
  if !sheet.columns.is_empty() {
    xml = xml + "<cols>"
    for index in 0..<sheet.columns.length() {
      let column = sheet.columns[index]
      xml = xml +
        "<col min=\"" +
        (index + 1).to_string() +
        "\" max=\"" +
        (index + 1).to_string() +
        "\" width=\"" +
        column.width.to_string() +
        "\" customWidth=\"1\"/>"
    }
    xml = xml + "</cols>"
  }
  xml = xml + "<sheetData><row r=\"1\">"
  for index in 0..<sheet.columns.length() {
    let column = sheet.columns[index]
    xml = xml +
      xlsx_inline_cell(xlsx_column_letter(index) + "1", column.label, 1)
  }
  xml = xml + "</row>"
  for row_index in 0..<sheet.rows.length() {
    let row_number = row_index + 2
    xml = xml + "<row r=\"" + row_number.to_string() + "\">"
    for column_index in 0..<sheet.columns.length() {
      let column = sheet.columns[column_index]
      let value = xlsx_cell_value(sheet.rows[row_index], column.field)
      let text = xlsx_text(value)
      if text.length() > XLSX_MAX_CELL_LENGTH {
        xml = xml +
          xlsx_inline_cell(
            xlsx_column_letter(column_index) + row_number.to_string(),
            text[:XLSX_MAX_CELL_LENGTH].to_owned(),
            xlsx_style(column.kind),
          )
      } else {
        match value {
          Number(number, ..) =>
            xml = xml +
              xlsx_number_cell(
                xlsx_column_letter(column_index) + row_number.to_string(),
                number.to_string(),
                xlsx_style(column.kind),
              )
          _ =>
            if text.is_empty() {
              ()
            } else {
              xml = xml +
                xlsx_inline_cell(
                  xlsx_column_letter(column_index) + row_number.to_string(),
                  text,
                  xlsx_style(column.kind),
                )
            }
        }
      }
    }
    xml = xml + "</row>"
  }
  xml +
  "</sheetData><sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/><selection pane=\"bottomLeft\" activeCell=\"A2\" sqref=\"A2\"/></sheetView></sheetViews><pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/></worksheet>"
}

///|
fn xlsx_styles_xml() -> String {
  "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
  "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><numFmts count=\"4\"><numFmt numFmtId=\"164\" formatCode=\"#,##0.00\"/><numFmt numFmtId=\"165\" formatCode=\"#,##0.##\"/><numFmt numFmtId=\"166\" formatCode=\"0.00%\"/><numFmt numFmtId=\"167\" formatCode=\"yyyy-mm-dd\"/></numFmts><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill><fill><patternFill patternType=\"solid\"><fgColor rgb=\"FFD9EAF7\"/><bgColor indexed=\"64\"/></patternFill></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"6\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"0\" applyFont=\"1\"/><xf numFmtId=\"164\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/><xf numFmtId=\"165\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/><xf numFmtId=\"166\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/><xf numFmtId=\"167\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"
}

///|
fn xlsx_zip_entry(name : String, xml : String) -> XlsxZipEntry {
  let data = @encoding/utf8.encode(xml)
  { name, data, crc: xlsx_crc32(data) }
}

///|
fn xlsx_crc32(data : Bytes) -> Int64 {
  // Keep the CRC as an unsigned 32-bit value in MoonBit's non-negative Int
  // range so ordinary right shift is logical.
  let mut crc : Int64 = 0xFFFFFFFFL
  for byte in data {
    crc = crc ^ byte.to_int64()
    for _ in 0..<8 {
      crc = if (crc & 1L) != 0L { (crc >> 1) ^ 0xEDB88320L } else { crc >> 1 }
    }
  }
  crc ^ 0xFFFFFFFFL
}

///|
fn xlsx_push_u16(output : Array[Byte], value : Int) -> Unit {
  output.push((value & 255).to_byte())
  output.push(((value >> 8) & 255).to_byte())
}

///|
fn xlsx_push_u32(output : Array[Byte], value : Int) -> Unit {
  output.push((value & 255).to_byte())
  output.push(((value >> 8) & 255).to_byte())
  output.push(((value >> 16) & 255).to_byte())
  output.push(((value >> 24) & 255).to_byte())
}

///|
fn xlsx_push_u32_64(output : Array[Byte], value : Int64) -> Unit {
  output.push((value & 255L).to_byte())
  output.push(((value >> 8) & 255L).to_byte())
  output.push(((value >> 16) & 255L).to_byte())
  output.push(((value >> 24) & 255L).to_byte())
}

///|
fn xlsx_push_bytes(output : Array[Byte], bytes : Bytes) -> Unit {
  for byte in bytes {
    output.push(byte)
  }
}

///|
fn xlsx_zip(entries : Array[XlsxZipEntry]) -> Bytes {
  let output : Array[Byte] = []
  let offsets : Array[Int] = []
  for entry in entries {
    offsets.push(output.length())
    let name = @encoding/utf8.encode(entry.name)
    xlsx_push_u32(output, 0x04034B50)
    xlsx_push_u16(output, 20)
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u32_64(output, entry.crc)
    xlsx_push_u32(output, entry.data.length())
    xlsx_push_u32(output, entry.data.length())
    xlsx_push_u16(output, name.length())
    xlsx_push_u16(output, 0)
    xlsx_push_bytes(output, name)
    xlsx_push_bytes(output, entry.data)
  }
  let central_offset = output.length()
  for index in 0..<entries.length() {
    let entry = entries[index]
    let name = @encoding/utf8.encode(entry.name)
    xlsx_push_u32(output, 0x02014B50)
    xlsx_push_u16(output, 20)
    xlsx_push_u16(output, 20)
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u32_64(output, entry.crc)
    xlsx_push_u32(output, entry.data.length())
    xlsx_push_u32(output, entry.data.length())
    xlsx_push_u16(output, name.length())
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u16(output, 0)
    xlsx_push_u32(output, 0)
    xlsx_push_u32(output, offsets[index])
    xlsx_push_bytes(output, name)
  }
  let central_size = output.length() - central_offset
  xlsx_push_u32(output, 0x06054B50)
  xlsx_push_u16(output, 0)
  xlsx_push_u16(output, 0)
  xlsx_push_u16(output, entries.length())
  xlsx_push_u16(output, entries.length())
  xlsx_push_u32(output, central_size)
  xlsx_push_u32(output, central_offset)
  xlsx_push_u16(output, 0)
  let fixed : FixedArray[Byte] = FixedArray::make(output.length(), 0)
  for index in 0..<output.length() {
    fixed[index] = output[index]
  }
  fixed.unsafe_reinterpret_as_bytes()
}

///|
fn xlsx_content_types_xml(sheet_count : Int) -> String {
  let mut xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
  for index in 0..<sheet_count {
    xml = xml +
      "<Override PartName=\"/xl/worksheets/sheet" +
      (index + 1).to_string() +
      ".xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
  }
  xml + "</Types>"
}

///|
fn xlsx_workbook_xml(sheets : Array[XlsxSheet]) -> String {
  let mut xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"
  for index in 0..<sheets.length() {
    xml = xml +
      "<sheet name=\"" +
      xlsx_xml_text(sheets[index].name) +
      "\" sheetId=\"" +
      (index + 1).to_string() +
      "\" r:id=\"rId" +
      (index + 1).to_string() +
      "\"/>"
  }
  xml + "</sheets></workbook>"
}

///|
fn xlsx_workbook_rels_xml(sheet_count : Int) -> String {
  let mut xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
  for index in 0..<sheet_count {
    xml = xml +
      "<Relationship Id=\"rId" +
      (index + 1).to_string() +
      "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet" +
      (index + 1).to_string() +
      ".xml\"/>"
  }
  xml +
  "<Relationship Id=\"rId" +
  (sheet_count + 1).to_string() +
  "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
}

///|
async fn xlsx_export(body : Json) -> (String, Bytes) raise CompanyServiceError {
  let sheets = xlsx_json_array(body, "sheets")
  if sheets.is_empty() {
    raise reject(422, "sheets must not be empty")
  }
  if sheets.length() > XLSX_MAX_SHEETS {
    raise reject(422, "too many sheets")
  }
  let parsed : Array[XlsxSheet] = []
  for index in 0..<sheets.length() {
    parsed.push(xlsx_parse_sheet(sheets[index], index))
  }
  let mut cells = 0
  for sheet in parsed {
    cells = cells + sheet.columns.length() * (sheet.rows.length() + 1)
    if cells > XLSX_MAX_CELLS {
      raise reject(422, "export exceeds cell limit")
    }
  }
  let entries : Array[XlsxZipEntry] = []
  entries.push(
    xlsx_zip_entry(
      "[Content_Types].xml",
      xlsx_content_types_xml(parsed.length()),
    ),
  )
  entries.push(
    xlsx_zip_entry(
      "_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/></Relationships>",
    ),
  )
  entries.push(
    xlsx_zip_entry(
      "docProps/core.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:creator>MoonSuite</dc:creator><cp:lastModifiedBy>MoonSuite</cp:lastModifiedBy></cp:coreProperties>",
    ),
  )
  entries.push(
    xlsx_zip_entry(
      "docProps/app.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>MoonSuite</Application></Properties>",
    ),
  )
  entries.push(xlsx_zip_entry("xl/workbook.xml", xlsx_workbook_xml(parsed)))
  entries.push(
    xlsx_zip_entry(
      "xl/_rels/workbook.xml.rels",
      xlsx_workbook_rels_xml(parsed.length()),
    ),
  )
  entries.push(xlsx_zip_entry("xl/styles.xml", xlsx_styles_xml()))
  for index in 0..<parsed.length() {
    entries.push(
      xlsx_zip_entry(
        "xl/worksheets/sheet" + (index + 1).to_string() + ".xml",
        xlsx_worksheet_xml(parsed[index]),
      ),
    )
  }
  let filename = xlsx_safe_filename(json_text(body, "filename", "export.xlsx"))
  (filename, xlsx_zip(entries))
}
