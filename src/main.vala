using Gee;

const string BOLD = "\033[1m";
const string RED = "\033[31m";
const string GREEN = "\033[32m";
const string YELLOW = "\033[33m";
const string MAGENTA = "\033[35m";
const string CYAN = "\033[36m";
const string RESET = "\033[0m";

private Regex color_matcher = null;

string join(string[] items, string sep) {
  if (items.length == 0) {
    return "";
  } else if (items.length == 1) {
    return items[0];
  } else {
    var res = items[0];
    foreach (var item in items[1:items.length]) {
      res += @"$sep$item";
    }
    return res;
  }
}

void vprint(string message, va_list args) {
  if (color_matcher == null) {
    color_matcher = /!\[(.+?)\]/;
  }
  try {
    message = color_matcher.replace_eval(message, -1, 0, 0,
      (m, res) => {
        switch (m.fetch(1)) {
        case "bold": res.append(BOLD); break;
        case "red": res.append(RED); break;
        case "green": res.append(GREEN); break;
        case "yellow": res.append(YELLOW); break;
        case "magenta": res.append(MAGENTA); break;
        case "cyan": res.append(CYAN); break;
        case "reset": case "/": res.append(RESET); break;
        }
        return false;
      });
    stdout.vprintf(@"$message$RESET", args);
  } catch (RegexError e) {
    stdout.printf("INTERNAL ERROR: RegexError: %s\n", e.message);
    Process.exit(1);
  }
}

void print(string message, ...) {
  var args = va_list();
  vprint(message, args);
}

void blankln() {
  stdout.putc('\n');
}

void println(string message, ...) {
  var args = va_list();
  vprint(message, args);
  blankln();
}

void warn(string message, ...) {
  var args = va_list();
  vprint(@"![bold]![magenta]Warning: ![reset]$message", args);
  blankln();
}

void fail(string message, ...) {
  var args = va_list();
  vprint(@"![bold]![red]Error: ![reset]$message", args);
  blankln();
  Process.exit(1);
}

abstract class UnitPath {
  public HashMap<string, string> props { get; protected set; }
  public string description { get; protected set; }

  private File retrieve_cache = null;

  public static UnitPath[] parse_paths(string paths) {
    UnitPath[] result = {};
    foreach (var item in paths.split(",")) {
      result += UnitPath.parse(item);
    }
    return result;
  }

  public static UnitPath parse(string path_, File? relative_to = null) {
    var path = path_;
    var props = new HashMap<string, string>();

    if ("{" in path) {
      var re_props = /^(.+){(.+)}$/;
      var re_pair = /^([a-zA-Z0-9_]+)=(.+)$/;

      MatchInfo match_props;
      if (!re_props.match(path, 0, out match_props)) {
        fail("Invalid unit path: %s", path);
      }

      path = match_props.fetch(1);
      foreach (var pair in match_props.fetch(2).split(":")) {
        MatchInfo match_pair;
        if (!re_pair.match(pair, 0, out match_pair)) {
          fail("Invalid argument pair in unit path: %s, %s", pair, path);
        }

        props[match_pair.fetch(1)] = match_pair.fetch(2);
      }
    }

    if (path.has_prefix("file:")) {
      var file_path = path[5:path.length];
      if (relative_to != null && file_path[0] != '/') {
        file_path = @"$(relative_to.get_path())/$file_path";
      }
      return new FileUnitPath(props, path, file_path);
    }
    fail("Invalid unit path: %s", path);
    return (UnitPath)null;
  }

  protected abstract File internal_retrieve();

  public File retrieve() {
    if (retrieve_cache == null) {
      retrieve_cache = internal_retrieve();
    }
    return retrieve_cache;
  }
}

class FileUnitPath : UnitPath {
  public File file { get; protected set; }

  public FileUnitPath(HashMap<string, string> props, string description, string file) {
    this.props = props;
    this.description = description;
    this.file = File.new_for_path(file);
  }

  protected override File internal_retrieve() {
    if (!file.query_exists()) {
      fail("Unit file %s does not exist.", file.get_path());
    }

    return file;
  }
}

class SystemProvider {
  private static File data_dir_cache = null;

  public static File get_storage_dir() {
    return File.new_for_path("/var/lib/isolatekit");
  }

  public static File get_data_dir() {
    if (data_dir_cache == null) {
      try {
        var contents = FileUtils.read_link("/proc/self/exe");
        var utf8 = Filename.to_utf8(contents, -1, null, null);
        data_dir_cache = File.new_for_path(utf8)
                          .get_parent().get_parent()
                          .get_child("share").get_child("isolatekit");
      } catch (FileError e) {
        fail("Failed to read /proc/self/exe: %s", e.message);
      } catch (ConvertError e) {
        fail("Failed to convert /proc/self/exe link to UTF-8: %s", e.message);
      }
    }

    return data_dir_cache;
  }

  public static File get_rc() {
    var result = get_data_dir().get_child("bin").get_child("rc");
    if (!result.query_exists()) {
      fail("rc executable at %s does not exist.", result.get_path());
    }
    return result;
  }

  public static File get_script(string name) {
    var result = get_data_dir().get_child("scripts").get_child(@"$name.rc");
    if (!result.query_exists()) {
      fail("Script %s does not exist.", result.get_path());
    }
    return result;
  }

  public static File get_temporary_dir(string desc) {
    var suffix = desc == null ? "" : @"-$(desc.replace("/", "_"))";
    try {
      return File.new_for_path(DirUtils.make_tmp(@"XXXXXX$suffix"));
    } catch (FileError e) {
      fail("Failed to get temporary directory: %s", e.message);
      return (File)null;
    }
  }

  public static File get_temporary_file(string desc) {
    FileIOStream ios;
    var suffix = desc == null ? "" : @"-$(desc.replace("/", "_"))";
    try {
      var tmp = File.new_tmp(@"XXXXXX$suffix", out ios);
      ios.close();
      return tmp;
    } catch (Error e) {
      fail("Failed to get temporary file: %s", e.message);
      return (File)null;
    }
  }

  public static void mkdir_p(File dir) {
    if (DirUtils.create_with_parents(dir.get_path(), 0600) == -1) {
      fail("Failed to create directory %s: %s", dir.get_path(), strerror(errno));
    }
  }

  public static void recursive_remove(File path) {
    FileEnumerator enumerator = null;

    try {
      enumerator = path.enumerate_children("standard::*",
                                           FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
    } catch (Error e) {
      warn("Failed to enumerate files inside %s for deletion: %s", path.get_path(),
           e.message);
      return;
    }

    while (true) {
      FileInfo info = null;

      try {
        info = enumerator.next_file();
      } catch (Error e) {
        warn("Failed to enumerate next file inside %s: %s", path.get_path(), e.message);
        break;
      }

      if (info == null) {
        break;
      }

      var child = path.resolve_relative_path(info.get_name());
      if (info.get_file_type() == FileType.DIRECTORY) {
        recursive_remove(child);
      } else {
        try {
          child.delete();
        } catch (Error e) {
          warn("Failed to delete %s while deleting %s: %s", path.get_path(),
               child.get_path(), e.message);
        }
      }
    }

    try {
      path.delete();
    } catch (Error e) {
      warn("Failed to delete %s: %s", path.get_path(), e.message);
    }
  }

  public static void mount(string source, string target, string type,
                           Linux.MountFlags flags = 0, string options = "") {
    if (Linux.mount(source, target, type, flags, options) == -1) {
      fail("Failed to mount %s: %s", target, strerror(errno));
    }
  }

  public static void bindmount(string source, string target, bool ro = true) {
    var flags = Linux.MountFlags.BIND;
    if (ro) {
      flags |= Linux.MountFlags.RDONLY;
    }
    SystemProvider.mount(source, target, "", flags);
  }

  public static void umount(string target) {
    if (Linux.umount(target) == -1) {
      fail("Failed to unmount %s: %s", target, strerror(errno));
    }
  }
}

enum UnitType { BASE, BUILDER }

struct Unit {
  string name;
  UnitType type;
  string rel;
  Unit[] deps;
  string[] expected_props;
  HashMap<string, string> given_props;
  string path;
  File script;
}

struct UnitStorageData {
  File base;
  File root;
  File config;
  File script;

  public static UnitStorageData new_for_unit(Unit unit) {
    var sha_builder = new Checksum(ChecksumType.SHA256);
    sha_builder.update((uchar[])unit.name, unit.name.length);
    foreach (var entry in unit.given_props.entries) {
      sha_builder.update((uchar[])";", 1);
      sha_builder.update((uchar[])entry.key, entry.value.length);
      sha_builder.update((uchar[])"=", 1);
      sha_builder.update((uchar[])entry.value, entry.value.length);
    }

    var sha = sha_builder.get_string();
    var storage = SystemProvider.get_storage_dir().get_child(sha);

    return UnitStorageData() {
      base = storage,
      root = storage.get_child("root"),
      config = storage.get_child("config"),
      script = storage.get_child("script.rc")
    };
  }
}

Unit[] read_units(UnitPath[] unit_paths, Unit[]? units_ = null,
                  HashMap<string, int>? index_map_ = null) {
  var units = units_ ?? new Unit[]{};
  var index_map = index_map_ ?? new HashMap<string, int>();

  var rc = SystemProvider.get_rc();
  var queryunit = SystemProvider.get_script("queryunit");
  var temp = SystemProvider.get_temporary_file("queryunit");

  foreach (var unit_path in unit_paths) {
    var unit_script = unit_path.retrieve();

    string[] command = {rc.get_path(), "-e", queryunit.get_path(),
                        unit_path.retrieve().get_path(), temp.get_path()};
    int status = 0;

    try {
      Process.spawn_sync(Environment.get_current_dir(), command, Environ.get(), 0,
                         null, null, null, out status);
    } catch (SpawnError e) {
      fail("Spawning queryunit for %s failed: %s", unit_path.description, e.message);
    }

    if (status != 0) {
      fail("queryunit of %s failed.", unit_path.description);
    }

    var kf = new KeyFile();
    try {
      kf.load_from_file(temp.get_path(), KeyFileFlags.NONE);

      if (kf.has_group("Error")) {
        fail("%s: %s", unit_path.description, kf.get_string("Error", "Message"));
      }

      UnitType type = kf.get_string("Result", "Type") == "base" ? UnitType.BASE :
                      UnitType.BUILDER;
      UnitPath[] dep_paths = {};
      foreach (var dep_string in kf.get_string_list("Result", "Deps")) {
        dep_paths += UnitPath.parse(dep_string, unit_path.retrieve().get_parent());
      }

      var deps = read_units(dep_paths, units, index_map);

      var unit = Unit() {
        name = kf.get_string("Result", "Name"),
        type = type,
        rel = kf.get_string("Result", "Rel"),
        deps = deps,
        expected_props = kf.get_string_list("Result", "Props"),
        given_props = unit_path.props,
        path = unit_path.description,
        script = unit_script
      };

      if (index_map.has_key(unit.name)) {
        var other_unit = units[index_map[unit.name]];
        if (unit.type != other_unit.type || unit.rel != other_unit.rel) {
          fail("Unit %s is self-inconsistent.", unit.name);
        }

        foreach (var entry in unit.given_props.entries) {
          if (other_unit.given_props.has_key(entry.key)) {
            warn("Unit %s has inconsistent props between two instances: %s={%s,%s}",
                 unit.name, entry.key, other_unit.given_props[entry.key], entry.value);
          } else {
            other_unit.given_props[entry.key] = entry.value;
          }
        }
      } else {
        index_map[unit.name] = units.length;
        units += unit;
      }
    } catch (Error e) {
      fail("Failed to load key-value queryunit data for %s from %s: %s",
           unit_path.description, temp.get_path(), e.message);
    }
  }

  if (units.length != 0) {
    if (units[0].type != UnitType.BASE) {
      fail("First unit %s must be a base.", units[0].name);
    }
    foreach (var unit in units[1:units.length]) {
      if (unit.type != UnitType.BUILDER) {
        fail("%s is not the first unit, and therefore should not be a base.",
             unit.name);
      }
    }
  }

  return units;
}

void run_in_unit(string name, File? storage_base_, Unit[] layers, string[] run_command,
                 File? script = null)
    requires (storage_base_ != null || layers.length != 0) {
  var storage_base = storage_base_ ??
                      SystemProvider.get_temporary_dir(@"$name-null-storage");

  var rootdir = storage_base.get_child("root");
  SystemProvider.mkdir_p(rootdir);

  if (script != null) {
    SystemProvider.bindmount(script.get_path(), "/run/isolatekit/script");
  }

  File mountroot = null;

  if (layers.length != 0) {
    var workdir = storage_base.get_child("work");
    if (workdir.query_exists()) {
      SystemProvider.recursive_remove(workdir);
    }
    SystemProvider.mkdir_p(workdir);

    mountroot = SystemProvider.get_temporary_dir(@"$name-overlay-mountroot");

    string[] options = {};
    string[] lower = {};

    foreach (var layer in layers) {
      var layer_storage = UnitStorageData.new_for_unit(layer);
      lower += layer_storage.root.get_path().replace(":", "\\:");
    }

    options += @"lowerdir=$(join(lower, ":"))";
    options += @"upperdir=$(rootdir.get_path())";
    options += @"workdir=$(workdir.get_path())";

    SystemProvider.mount("overlay", mountroot.get_path(), "overlay", 0,
                         join(options, ","));
  } else {
    mountroot = rootdir;
  }

  SystemProvider.mkdir_p(mountroot.get_child("run").get_child("isolatekit")
                                  .get_child("data"));

  // XXX: using string[] command = {...} here causes a C compilation error.
  var command = new string[]{"systemd-nspawn", "--register=no",
                             "--bind-ro=/run/isolatekit/data",
                             "--bind-ro=/run/isolatekit/script",
                             "-D", mountroot.get_path(), "--chdir=/", "-q",
                             "-M", name.replace("/", "_"), "-u", "0"};

  foreach (var item in run_command) {
    command += item;
  }

  int status;
  try {
    Process.spawn_sync(Environment.get_current_dir(), command, Environ.get(),
                       SpawnFlags.SEARCH_PATH | SpawnFlags.CHILD_INHERITS_STDIN, null,
                       null, null, out status);
  } catch (SpawnError e) {
    fail("Spawning %s for %s failed: %s", join(run_command, " "), name, e.message);
  }

  if (status != 0) {
    if (script == null) {
      Process.exit(Process.exit_status(status));
    } else {
      fail("%s of %s failed.", join(run_command, " "), name);
    }
  }

  if (script != null) {
    SystemProvider.umount("/run/isolatekit/script");
  }
}

void ensure_units(Unit[] units) {
  var createunit = SystemProvider.get_script("createunit");
  var rc = SystemProvider.get_rc();

  foreach (var unit in units) {
    var storage = UnitStorageData.new_for_unit(unit);

    print("Processing unit ![cyan]%s![/]... ", unit.name);

    if (storage.base.query_exists()) {
      if (storage.config.query_exists()) {
        try {
          var kf = new KeyFile();
          kf.load_from_file(storage.config.get_path(), KeyFileFlags.NONE);
          if (kf.get_string("Unit", "Rel") == unit.rel) {
            println("already exists");
            continue;
          }
        } catch (Error e) {
          warn("Error reading %s storage config: %s", unit.name, e.message);
        }
      }

      SystemProvider.recursive_remove(storage.base);
    }

    blankln();

    SystemProvider.mkdir_p(storage.root);

    string[] command = {rc.get_path(), "-e", createunit.get_path(),
                        unit.script.get_path(), storage.root.get_path()};
    foreach (var entry in unit.given_props.entries) {
      var found = false;
      foreach (var prop in unit.expected_props) {
        if (prop == entry.key) {
          found = true;
          command += entry.key;
          command += entry.value;
          break;
        }
      }

      if (!found) {
        fail("Unknown prop: %s{%s=%s}", unit.path, entry.key, entry.value);
      }
    }

    var tmp = SystemProvider.get_temporary_dir("createunit");

    if (unit.type == UnitType.BASE) {
      int status = 0;
      try {
        Process.spawn_sync(tmp.get_path(), command, Environ.get(), 0, null, null, null,
                           out status);
      } catch (SpawnError e) {
        fail("Spawning createunit for %s failed: %s", unit.name, e.message);
      }

      if (status != 0) {
        fail("createunit of %s failed.", unit.name);
      }
    }

    try {
      unit.script.copy(storage.script, 0);
    } catch (Error e) {
      fail("Error saving script file at %s to %s: %s", unit.script.get_path(),
           storage.script.get_path(), e.message);
    }

    Unit[] layers = {};
    string func = "setup";
    if (unit.type == UnitType.BUILDER) {
      layers += units[0];
      func = "run";
    }

    string[] run_command = {"/run/isolatekit/data/bin/rc", "-e",
                            "/run/isolatekit/data/scripts/rununit.rc", func};
    foreach (var entry in unit.given_props.entries) {
      run_command += entry.key;
      run_command += entry.value;
    }

    run_in_unit(unit.name, storage.base, layers, run_command, unit.script);

    string[] dep_strings = {};
    foreach (var dep in unit.deps) {
      dep_strings += dep.path;
    }

    var kf = new KeyFile();
    kf.set_string("Unit", "Name", unit.name);
    kf.set_string("Unit", "Type", unit.type == UnitType.BASE ? "base" : "builder");
    kf.set_string("Unit", "Rel", unit.rel);
    kf.set_string("Unit", "Path", unit.path);
    kf.set_string_list("Unit", "ExpectedProps", unit.expected_props);
    kf.set_string_list("Unit", "Deps", dep_strings);

    foreach (var entry in unit.given_props.entries) {
     kf.set_string("GivenProps", entry.key, entry.value);
    }

    try {
      kf.save_to_file(storage.config.get_path());
    } catch (FileError e) {
      fail("Error saving unit config to %s: %s", storage.config.get_path(), e.message);
    }
  }
}

abstract class Command {
  public abstract string name { get; }
  public abstract string usage { get; }
  public abstract string description { get; }
  public abstract void run(string[] args);
}

class TargetCommand : Command {
  public override string name {
    get { return "target"; }
  }
  public override string usage {
    get { return "set|run ![yellow]<target>![/]"; }
  }
  public override string description {
    get { return "Manipulate or run a target."; }
  }

  private static string arg_add;
  private static string arg_remove;

  public const OptionEntry[] options = {
    {"add", 'a', 0, OptionArg.STRING, ref arg_add, "Add units to this target", "UNITS"},
    {"remove", 'r', 0, OptionArg.STRING, ref arg_remove,
     "Remove units from this target", "UNITS"},
  };

  public override void run(string[] args) {
    if (args.length != 2) {
      fail("Expected 2 arguments, got %d.", args.length);
    } else if (args[0] != "set" && args[0] != "run") {
      fail("Expected 'set' or 'run', got '%s'.", args[0]);
    }

    if (args[1] != "null") {
      fail("TODO: support running non-null targets.");
    }

    if (args[1] == "null" && arg_add == null) {
      fail("Cannot run a null target without --add.");
    }

    var add_units = read_units(UnitPath.parse_paths(arg_add));
    if (add_units.length == 0) {
      fail("At least one unit is required.");
    }
    ensure_units(add_units);

    string[] command = {"/run/isolatekit/data/bin/rc", "-l", "/.isolatekit-enter"};
    run_in_unit("null", null, add_units, command);
  }
}

class UpdateCommand : Command {
  public override string name {
    get { return "update"; }
  }
  public override string usage {
    get { return "update"; }
  }
  public override string description {
    get { return "Update units or targets."; }
  }

  private static string arg_add;

  public const OptionEntry[] options = {
    {"add", 'a', 0, OptionArg.STRING, ref arg_add, "add", "UNITS"},
  };

  public override void run(string[] args) {
  }
}

class Main : Object {
  private static bool arg_help;

  const OptionEntry[] common_options = {
    {"help", 'h', 0, OptionArg.NONE, ref arg_help, "Show this screen.", null},
  };

  private static OptionEntry[] all_options = {};

  private static void print_short_options() {
    foreach (var opt in all_options) {
      if (opt.long_name == null || opt.long_name == "") {
        continue;
      }

      print(" ![green][-%c --%s", opt.short_name, opt.long_name);
      if (opt.arg_description != null) {
        print(@"![green]=<$(opt.arg_description)>");
      }
      print("![green]]");
    }
  }

  private static void print_usage(Command? command) {
    if (command == null) {
      print("![cyan]Usage:![/] ik ![yellow]<command>");
      print_short_options();
      blankln();
      blankln();
      println("  IsolateKit allows you to create isolated development environments.");
      blankln();

      println("![cyan]Commands:");
      blankln();

      Command[] commands = {new TargetCommand(), new UpdateCommand()};
      foreach (var cmd in commands) {
        println("![yellow]  %-8s![/]%s", cmd.name, cmd.description);
      }
    } else {
      print(@"![cyan]Usage:![/] ik $(command.name) $(command.usage)");
      print_short_options();
      blankln();
      blankln();
      println("  %s", command.description);
    }

    blankln();
    println("![cyan]Options:");
    blankln();

    foreach (var opt in all_options) {
      if (opt.long_name == null || opt.long_name == "") {
        continue;
      }

      println("  ![green]-%c --%-7s![/]%s", opt.short_name, opt.long_name,
              opt.description);
    }
  }

  private static void append_options(OptionEntry[] options) {
    foreach (var opt in options) {
      all_options += opt;
    }
  }

  public static int main(string[] args) {
    append_options((OptionEntry[])common_options);

    Command? command = null;

    if (args.length > 1) {
      switch (args[1]) {
      case "target":
        command = new TargetCommand();
        append_options((OptionEntry[])TargetCommand.options);
        break;
      case "update":
        command = new UpdateCommand();
        append_options((OptionEntry[])UpdateCommand.options);
        break;
      }
    }

    all_options += OptionEntry() { long_name = null };

    var opt = new OptionContext();
    opt.add_main_entries((OptionEntry[])all_options, null);
    opt.set_help_enabled(false);

    try {
      opt.parse(ref args);
    } catch (OptionError e) {
      fail("%s.", e.message);
      }

    if (arg_help) {
      print_usage(command);
      return 0;
    }

    if (command == null) {
      fail("No command given.");
    }

    if (Linux.unshare(Linux.CloneFlags.NEWNS) == -1) {
      fail("Failed to unshare mount namespace: %s", strerror(errno));
    }

    SystemProvider.mount("none", "/", "",
                         Linux.MountFlags.PRIVATE | Linux.MountFlags.REC, "");
    SystemProvider.mount("tmpfs", "/run/isolatekit/tmp", "tmpfs", 0, "");
    SystemProvider.bindmount(SystemProvider.get_data_dir().get_path(),
                             "/run/isolatekit/data");

    Environment.set_variable("TMPDIR", "/run/isolatekit/tmp", true);

    command.run(args[2:args.length]);

    return 0;
  }
}
