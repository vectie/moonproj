///|
pub(all) suberror MappingVariantError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn run(
  input : String,
  output : String,
  version : String,
) -> Unit raise MappingVariantError {
  let content = @fs.read_file_to_string(input) catch {
    error => raise MappingVariantError::Io(error)
  }
  let parsed = @json.parse(content) catch {
    _ => raise MappingVariantError::InvalidInput("invalid JSON")
  }
  let fields = match parsed {
    Object(fields) => fields
    _ =>
      raise MappingVariantError::InvalidInput("mapping root must be an object")
  }
  fields.set("mapping_version", Json::string(version))
  @fs.write_string_to_file(
    output,
    Json::object(fields).stringify(indent=2) + "\n",
  ) catch {
    error => raise MappingVariantError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output),
      "mapping_version": Json::string(version),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: mapping_variant <mapping.json> <output.json> <mapping-version>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    MappingVariantError::InvalidInput(message) => {
      println("mapping variant failed: " + message)
      @sys.exit(1)
    }
    MappingVariantError::Io(_) => {
      println("mapping variant failed: filesystem error")
      @sys.exit(1)
    }
  }
}
