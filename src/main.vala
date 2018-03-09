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

[NoReturn]
void fail(string message, ...) {
  var args = va_list();
  vprint(@"![bold]![red]Error: ![reset]$message", args);
  blankln();
  Process.exit(1);
}

string sha256(string s) {
  var sha_builder = new Checksum(ChecksumType.SHA256);
  sha_builder.update((uchar[])s, s.length);
  return sha_builder.get_string();
}

abstract class UnitPath {
  public HashMap<string, string> props { get; protected set; }
  public string path { get; protected set; }

  private File retrieve_cache = null;

  public static UnitPath[] parse_paths(string paths) {
    UnitPath[] result = {};
    foreach (var item in paths.split(",")) {
      result += UnitPath.parse(item);
    }
    return result;
  }

  public static UnitPath parse(string path_, string? relative_to_ = null) {
    var path = path_;
    var props = new HashMap<string, string>();
    var relative_to = relative_to_ ?? Environment.get_current_dir();

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
      if (relative_to != null && !Path.is_absolute(file_path)) {
        file_path = @"$relative_to/$file_path";
      }
      return new FileUnitPath(props, @"file:$file_path", file_path);
    } else if (path.has_prefix("git:") || path.has_prefix("github:")) {
      var colon = path.index_of_char(':');
      var prefix = path[0:colon];
      var url_and_file = path[colon + 1:path.length];

      var slash = url_and_file.index_of("//");
      if (slash == -1) {
        fail("Unit path %s must use // to separate repository and file.", path);
      }
      var url = url_and_file[0:slash];
      var file = url_and_file[slash + 2:url_and_file.length];

      MatchInfo match;
      var is_repo = /^([^\/]+)\/([^\/]+)$/.match(url, 0, out match);
      if (prefix != "git" && !is_repo) {
        fail("Invalid repo in unit path: %s", path);
      }

      if (is_repo) {
        url = @"https://github.com/$url";
      }
      return new GitUnitPath(props, path, url, file);
    }

    fail("Invalid unit path: %s", path);
  }

  protected abstract File internal_retrieve(bool update);

  public File retrieve(bool update = false) {
    if (retrieve_cache == null || !update) {
      retrieve_cache = internal_retrieve(update);
    }
    return retrieve_cache;
  }
}

class FileUnitPath : UnitPath {
  public File file { get; protected set; }

  public FileUnitPath(HashMap<string, string> props, string path, string file) {
    this.props = props;
    this.path = path;
    this.file = File.new_for_path(file);
  }

  protected override File internal_retrieve(bool update) {
    if (!file.query_exists()) {
      fail("Unit file %s does not exist.", file.get_path());
    }

    return file;
  }
}

class GitUnitPath : UnitPath {
  private string url;
  private string file;

  public GitUnitPath(HashMap<string, string> props, string path, string url,
                     string file) {
    this.props = props;
    this.path = path;
    this.url = url;
    this.file = file;
  }

  protected override File internal_retrieve(bool update) {
    var repo_storage = SystemProvider.get_storage_dir().get_child("repo");
    var id = sha256(url);
    var repo = repo_storage.get_child(id);
    var test = repo.get_child(".isolatekit-test");

    if (!test.query_exists()) {
      println("Running ![cyan]git clone![/] ![magenta]%s![/]...", url);

      if (repo.query_exists()) {
        SystemProvider.recursive_remove(repo);
      }
      SystemProvider.mkdir_p(repo);
      int status;

      try {
        string[] command = {"git", "clone", url, repo.get_path()};
        Process.spawn_sync(Environment.get_current_dir(), command, Environ.get(),
                           SpawnFlags.SEARCH_PATH, null, null, null, out status);
      } catch (SpawnError e) {
        fail("Failed to spawn git: %s", e.message);
      }

      if (status != 0) {
        fail("git failed with exit status %d.", status);
      }

      try {
        var os = test.create(FileCreateFlags.PRIVATE);
        os.close();
      } catch (Error e) {
        fail("Failed to write test file %s: %s", test.get_path(), e.message);
      }
    } else if (update) {
      println("Running ![cyan]git pull![/] for ![yellow]%s![/]...", url);

      int status;
      try {
        string[] command = {"git", "pull"};
        Process.spawn_sync(repo.get_path(), command, Environ.get(),
                           SpawnFlags.SEARCH_PATH, null, null, null, out status);
      } catch (SpawnError e) {
        fail("Failed to spawn git: %s", e.message);
      }

      if (status != 0) {
        fail("git failed with exit status %d.", status);
      }
    }

    var child = File.new_for_path(@"$(repo.get_path())/$file");
    if (!child.query_exists()) {
      fail("Failed to locate unit %s inside %s.", file, url);
    }

    return child;
  }
}

class SystemProvider {
  private static File self_cache = null;

  public static File get_storage_dir() {
    return File.new_for_path("/var/lib/isolatekit");
  }

  public static File get_self() {
    if (self_cache == null) {
      try {
        var contents = FileUtils.read_link("/proc/self/exe");
        var utf8 = Filename.to_utf8(contents, -1, null, null);
        self_cache = File.new_for_path(utf8);
      } catch (FileError e) {
        fail("Failed to read /proc/self/exe: %s", e.message);
      } catch (ConvertError e) {
        fail("Failed to convert /proc/self/exe link to UTF-8: %s", e.message);
      }
    }

    return self_cache;
  }

  public static File get_data_dir() {
    return get_self().get_parent().get_parent()
                     .get_child("share").get_child("isolatekit");
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
    }
  }

  public static void mkdir_p(File dir) {
    if (DirUtils.create_with_parents(dir.get_path(), 0600) == -1) {
      fail("Failed to create directory %s: %s", dir.get_path(), strerror(errno));
    }
  }

  public static File[] list(File path, FileType? file_type = null) {
    FileEnumerator enumerator = null;
    File[] files = {};

    try {
      enumerator = path.enumerate_children("standard::*",
                                           FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
    } catch (Error e) {
      warn("Failed to list %s: %s", path.get_path(), e.message);
      return files;
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

      if (file_type == null || info.get_file_type() == file_type) {
        files += path.get_child(info.get_name());
      } else {
        warn("Unexpected file %s of type %s inside %s.", info.get_name(),
             info.get_file_type().to_string(), path.get_path());
      }
    }

    return files;
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

struct UnitStorageData {
  string id;
  File base;
  File root;
  File config;
  File script;

  public static UnitStorageData new_for_unit_id(string id) {
    var storage = SystemProvider.get_storage_dir().get_child("unit").get_child(id);

    return UnitStorageData() {
      id = id,
      base = storage,
      root = storage.get_child("root"),
      config = storage.get_child("config"),
      script = storage.get_child("script.rc")
    };
  }

  public static UnitStorageData new_for_unit_name(string name,
                                                  HashMap<string, string> given_props) {
    var sha_builder = new Checksum(ChecksumType.SHA256);
    sha_builder.update((uchar[])name, name.length);
    foreach (var entry in given_props.entries) {
      sha_builder.update((uchar[])";", 1);
      sha_builder.update((uchar[])entry.key, entry.value.length);
      sha_builder.update((uchar[])"=", 1);
      sha_builder.update((uchar[])entry.value, entry.value.length);
    }

    var id = sha_builder.get_string();
    return new_for_unit_id(id);
  }
}

struct Unit {
  string name;
  UnitType type;
  string rel;
  bool dirty;
  Unit[] deps;
  string[] expected_props;
  HashMap<string, string> given_props;
  string path;
  File script;
  UnitStorageData storage;
}

Unit[] read_units_from_paths(UnitPath[] unit_paths, bool require_base = true,
                             Unit[]? units_ = null,
                             HashMap<string, int>? name_index_map_ = null,
                             HashMap<string, int>? path_index_map_ = null) {
  var units = units_ ?? new Unit[]{};
  var name_index_map = name_index_map_ ?? new HashMap<string, int>();
  var path_index_map = path_index_map_ ?? new HashMap<string, int>();

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
      fail("Spawning queryunit for %s failed: %s", unit_path.path, e.message);
    }

    if (status != 0) {
      fail("queryunit of %s failed.", unit_path.path);
    }

    Unit unit;

    if (path_index_map.has_key(unit_script.get_path())) {
      unit = units[path_index_map[unit_script.get_path()]];
    } {
      var kf = new KeyFile();
      try {
        kf.load_from_file(temp.get_path(), KeyFileFlags.NONE);

        if (kf.has_group("Error")) {
          fail("%s: %s", unit_path.path, kf.get_string("Error", "Message"));
        }

        string name = kf.get_string("Result", "Name");
        UnitType type = kf.get_string("Result", "Type") == "base" ? UnitType.BASE :
                        UnitType.BUILDER;
        UnitPath[] dep_paths = {};
        foreach (var dep_string in kf.get_string_list("Result", "Deps")) {
          dep_paths += UnitPath.parse(dep_string,
                                      unit_path.retrieve().get_parent().get_path());
        }

        var deps = read_units_from_paths(dep_paths, true, units, name_index_map,
                                         path_index_map);

        unit = Unit() {
          name = name,
          type = type,
          rel = kf.get_string("Result", "Rel"),
          dirty = false,
          deps = deps,
          expected_props = kf.get_string_list("Result", "Props"),
          given_props = unit_path.props,
          path = unit_path.path,
          script = unit_script,
          storage = UnitStorageData.new_for_unit_name(name, unit_path.props)
        };
      } catch (Error e) {
        fail("Failed to load key-value queryunit data for %s from %s: %s",
             unit_path.path, temp.get_path(), e.message);
      }
    }

    if (name_index_map.has_key(unit.name)) {
      var other_unit = units[name_index_map[unit.name]];
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
      name_index_map[unit.name] = units.length;
      path_index_map[unit_script.get_path()] = units.length;
      units += unit;
    }
  }

  if (units.length != 0) {
    int start = 0;
    if (require_base) {
      if (units[0].type != UnitType.BASE) {
        fail("First unit %s must be a base.", units[0].name);
      }
      start = 1;
    }
    foreach (var unit in units[start:units.length]) {
      if (unit.type != UnitType.BUILDER) {
        if (require_base) {
          fail("%s is not the first unit, and therefore should not be a base.",
               unit.name);
        } else {
          fail("%s must not be a base.", unit.name);
        }
      }
    }
  }

  return units;
}

// NOTE: This does NOT resolve dependencies, and it assumes all deps are already in
// the id list.
Unit[] read_units_from_ids(string[] unit_ids) {
  Unit[] units = {};
  var index_map = new HashMap<string, int>();

  foreach (var id in unit_ids) {
    var storage = UnitStorageData.new_for_unit_id(id);
    if (!storage.base.query_exists()) {
      fail("Unit with id %s does not exist.", id);
    }

    var kf = new KeyFile();
    try {
      kf.load_from_file(storage.config.get_path(), KeyFileFlags.NONE);

      var name = kf.get_string("Unit", "Name");
      var type = kf.get_string("Unit", "Type") == "base" ? UnitType.BASE
                 : UnitType.BUILDER;

      Unit[] deps = {};
      foreach (var dep_id in kf.get_string_list("Unit", "Deps")) {
        if (!index_map.has_key(dep_id)) {
          fail("Unit id %s should have come before %s (%s).", dep_id, id, name);
        }
        deps += units[index_map[dep_id]];
      }

      var given_props = new HashMap<string, string>();
      if (kf.has_group("GivenProps")) {
        foreach (var key in kf.get_keys("GivenProps")) {
          given_props[key] = kf.get_string("GivenProps", key);
        }
      }

      var unit = Unit() {
        name = name,
        type = type,
        rel = kf.get_string("Unit", "Rel"),
        dirty = false,
        deps = deps,
        expected_props = kf.get_string_list("Unit", "ExpectedProps"),
        given_props = given_props,
        path = kf.get_string("Unit", "Path"),
        script = storage.script,
        storage = storage
      };

      index_map[id] = units.length;
      units += unit;
    } catch (Error e) {
      fail("Failed to load unit config for id %s: %s", id, e.message);
    }
  }

  return units;
}

struct BindMount {
  bool rw;
  string source;
  string dest;

  public static BindMount[] parse(string binds_string, bool rw) {
    BindMount[] binds = {};

    var builder = new StringBuilder();
    var escape = false;
    string source = null;
    string dest = null;

    var index = 0;
    unichar c = 0;
    while (binds_string.get_next_char(ref index, out c)) {
      if (escape) {
        builder.append_unichar(c);
        escape = false;
      } else if (c == '\\') {
        escape = true;
      } else if (c == ':') {
        if (source != null) {
          fail("Bind mount %s should only have one : (use \\: to escape).",
               binds_string);
        }
        source = builder.str;
        builder.truncate();
      } else if (c == ',') {
        dest = builder.str;
        builder.truncate();

        binds += BindMount() {
          rw = rw,
          source = source ?? dest,
          dest = dest
        };
        source = dest = null;
      } else {
        builder.append_unichar(c);
      }
    }

    dest = builder.str;
    if (dest.length != 0) {
      binds += BindMount() {
        rw = rw,
        source = source ?? dest,
        dest = dest
      };
    }

    return binds;
  }
}

int run_in_unit(string name, File? storage_base_, Unit[] layers, string[] run_command,
                BindMount[] binds = {})
    requires (storage_base_ != null || layers.length != 0) {
  var storage_base = storage_base_ ??
                      SystemProvider.get_temporary_dir(@"$name-null-storage");

  var rootdir = storage_base.get_child("root");
  SystemProvider.mkdir_p(rootdir);

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
      lower += layer.storage.root.get_path().replace(":", "\\:");
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

  foreach (var bind in binds) {
    var arg = bind.rw ? "" : "-ro";
    var source = File.new_for_path(bind.source.replace(":", "\\:"))
                     .resolve_relative_path("").get_path();
    var dest = bind.dest.replace(":", "\\:");
    command += @"--bind$arg=$source:$dest";
  }

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

  return Process.exit_status(status);
}

void ensure_units(Unit[] units) {
  var createunit = SystemProvider.get_script("createunit");
  var rc = SystemProvider.get_rc();

  var dirty = new HashSet<string>();

  foreach (var unit in units) {
    if (unit.storage.base.query_exists()) {
      if (unit.storage.config.query_exists()) {
        try {
          var kf = new KeyFile();
          kf.load_from_file(unit.storage.config.get_path(), KeyFileFlags.NONE);
          if (kf.get_string("Unit", "Rel") != unit.rel) {
            unit.dirty = true;
          }
        } catch (Error e) {
          warn("Error reading %s storage config: %s", unit.name, e.message);
        }
      } else {
        unit.dirty = true;
      }

      if (!unit.dirty) {
        foreach (var dep in unit.deps) {
          if (dep.storage.id in dirty) {
            unit.dirty = true;
            break;
          }
        }
      }

      if (!unit.dirty) {
        continue;
      } else {
        dirty.add(unit.storage.id);
      }

      SystemProvider.recursive_remove(unit.storage.base);
    }

    println("Processing unit ![cyan]%s![/]... ", unit.name);

    SystemProvider.mkdir_p(unit.storage.root);

    string[] command = {rc.get_path(), "-e", createunit.get_path(),
                        unit.script.get_path(), unit.storage.root.get_path()};
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
      unit.script.copy(unit.storage.script, 0);
    } catch (Error e) {
      fail("Error saving script file at %s to %s: %s", unit.script.get_path(),
           unit.storage.script.get_path(), e.message);
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

    SystemProvider.bindmount(unit.script.get_path(), "/run/isolatekit/script");
    var ret = run_in_unit(unit.name, unit.storage.base, layers, run_command);
    SystemProvider.umount("/run/isolatekit/script");

    if (ret != 0) {
      fail("Unit script failed with exit status %d.", ret);
    }

    string[] dep_strings = {};
    foreach (var dep in unit.deps) {
      dep_strings += dep.storage.id;
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
      kf.save_to_file(unit.storage.config.get_path());
    } catch (FileError e) {
      fail("Failed to save unit config to %s: %s", unit.storage.config.get_path(),
           e.message);
    }
  }
}

struct Target {
  string name;
  string id;
  Unit[] units;
  File base;
  File config;
  File root;

  public static Target read(string name, out bool present) {
    var id = sha256(name);
    var storage = SystemProvider.get_storage_dir().get_child("target").get_child(id);

    present = false;

    string[] unit_ids = {};

    var config = storage.get_child("config");
    if (config.query_exists()) {
      var kf = new KeyFile();
      try {
        kf.load_from_file(config.get_path(), KeyFileFlags.NONE);
        foreach (var unit_id in kf.get_string_list("Target", "Units")) {
          unit_ids += unit_id;
        }
        present = true;
      } catch (Error e) {
        warn("Failed to read target %s: %s", name, e.message);
      }
    }

    return Target() {
      name = name,
      id = id,
      units = read_units_from_ids(unit_ids),
      base = storage,
      config = config,
      root = storage.get_child("root")
    };
  }

  public void save() {
    SystemProvider.mkdir_p(root);

    string[] unit_ids = {};
    foreach (var unit in units) {
      unit_ids += unit.storage.id;
    }

    var kf = new KeyFile();
    try {
      kf.set_string("Target", "Name", name);
      kf.set_string_list("Target", "Units", unit_ids);
      kf.save_to_file(config.get_path());
    } catch (Error e) {
      fail("Failed to save target %s: %s", name, e.message);
    }
  }
}

delegate void StorageMapDelegate(string name, File path, KeyFile kf);

string map_storage(string dirname, StorageMapDelegate dl) {
  var sect = dirname == "target" ? "Target" : "Unit";

  var dir = SystemProvider.get_storage_dir().get_child(dirname);
  if (!dir.query_exists()) {
    return sect;
  }

  foreach (var path in SystemProvider.list(dir, FileType.DIRECTORY)) {
    var config = path.get_child("config");

    var kf = new KeyFile();
    string name = null;
    try {
      kf.load_from_file(config.get_path(), KeyFileFlags.NONE);
      name = kf.get_string(sect, "Name");
    } catch (Error e) {
      warn("Failed to load %s: %s", path.get_path(), e.message);
      continue;
    }

    dl(name, path, kf);
  }

  return sect;
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
  private static string arg_bind_ro = null;
  private static string arg_bind_rw = null;

  public const OptionEntry[] options = {
    {"add", 'a', 0, OptionArg.STRING, ref arg_add, "Add units to this target.",
     "UNITS"},
    {"remove", 'r', 0, OptionArg.STRING, ref arg_remove,
     "Remove units from this target.", "UNITS"},
    {"bind-ro", 'b', 0, OptionArg.STRING, ref arg_bind_ro,
     "Bind mount the given directory in the running isolate (read-only).", "BIND"},
    {"bind-rw", 'B', 0, OptionArg.STRING, ref arg_bind_rw,
     "Bind mount the given directory in the running isolate (read-write).", "BIND"},
  };

  public override void run(string[] args) {
    if (args.length != 2) {
      fail("Expected 2 arguments, got %d.", args.length);
    } else if (args[0] != "set" && args[0] != "run") {
      fail("Expected 'set' or 'run', got '%s'.", args[0]);
    }

    Target? target = null;
    bool target_present = false;

    if (args[1] == "null") {
      if (args[0] == "set") {
        fail("Cannot set null target.");
      } else if (arg_add == null) {
        fail("Cannot run a null target without -a/--add.");
      }
    } else {
      target = Target.read(args[1], out target_present);
      if (args[0] == "run" && !target_present) {
        fail("Cannot run a non-existent target.");
      }
    }

    if (args[0] == "set" && (arg_bind_ro != null || arg_bind_rw != null)) {
      fail("-b/--bind-ro or -B/--bind-rw can only be passed to 'run'.");
    }

    BindMount[] binds = {};
    foreach (var bind in BindMount.parse(arg_bind_rw ?? "", true)) {
      binds += bind;
    }
    foreach (var bind in BindMount.parse(arg_bind_ro ?? "", false)) {
      binds += bind;
    }

    var add_units = read_units_from_paths(UnitPath.parse_paths(arg_add ?? ""),
                                          !target_present);
    var remove_units = read_units_from_paths(UnitPath.parse_paths(arg_remove ?? ""),
                                             false);

    Unit[] units = {};

    var ignore = new HashSet<string>();
    foreach (var unit in remove_units) {
      ignore.add(unit.storage.id);
    }

    for (int i = 0; i < 2; i++) {
      Unit[] unit_source;
      if (i == 0) {
        if (target == null) {
          continue;
        }
        unit_source = target.units;
      } else {
        unit_source = add_units;
      }
      foreach (var unit in unit_source) {
        if (!(unit.storage.id in ignore)) {
          units += unit;
          ignore.add(unit.storage.id);
        }
      }
    }

    ensure_units(units);

    if (args[0] == "set") {
      target.units = units;
      target.save();
    } else if (args[0] == "run") {
      string[] command = {"/run/isolatekit/data/bin/rc", "-l", "/.isolatekit-enter"};
      var storage_base = target != null ? target.base : null;
      Process.exit(run_in_unit("null", storage_base, units, command, binds));
    }
  }
}

class UpdateCommand : Command {
  public override string name {
    get { return "update"; }
  }
  public override string usage {
    get { return "![yellow]<units...>![/]"; }
  }
  public override string description {
    get { return "Update units."; }
  }

  public const OptionEntry[] options = {};

  public override void run(string[] args) {
    var update_all = args.length == 0;
    var to_update = new HashSet<string>();
    foreach (var arg in args) {
      to_update.add(arg);
    }

    var passed = new HashSet<string>();
    UnitPath[] paths = {};

    map_storage("unit", (name, _, kf) => {
      UnitPath path;

      if (!update_all && !(name in to_update)) {
        return;
      }

      try {
        path = UnitPath.parse(kf.get_string("Unit", "Path"));
      } catch (KeyFileError e) {
        fail("Failed to retrieve unit data for %s: %s", name, e.message);
      }

      path.retrieve(true);
      paths += path;
    });

    Unit[] units = {};

    foreach (var unit in read_units_from_paths(paths)) {
      if (!(unit.storage.id in passed)) {
        units += unit;
        passed.add(unit.storage.id);
      }
    }

    ensure_units(units);
  }
}

class ListCommand : Command {
  public override string name {
    get { return "list"; }
  }
  public override string usage {
    get { return "all|targets|units"; }
  }
  public override string description {
    get { return "List all targets and/or units."; }
  }

  private static bool arg_terse;

  public const OptionEntry[] options = {
    {"terse", 't', 0, OptionArg.NONE, ref arg_terse, "Show terse output.", null},
  };

  public override void run(string[] args) {
    if (args.length != 1) {
      fail("Expected 1 argument, got %d.", args.length);
    } else if (args[0] != "all" && args[0] != "targets" && args[0] != "units") {
      fail("Expected 'all', 'targets', or 'units', got '%s'.", args[0]);
    }

    string[] dirs = {};
    if (args[0] == "all" || args[0] == "targets") {
      dirs += "target";
    }
    if (args[0] == "all" || args[0] == "units") {
      dirs += "unit";
    }

    foreach (var dirname in dirs) {
      var items = new ArrayList<string>();
      var sect = map_storage(dirname, (name, path, kf) => {
        items.add(name);
      });

      if (items.size == 0) {
        continue;
      }
      items.sort();

      if (!arg_terse) {
        println("![yellow]%ss:", sect);
        foreach (var item in items) {
          println("  - %s", item);
        }
      } else {
        foreach (var item in items) {
          if (args[0] == "all") {
            println("%s: %s", dirname, item);
          } else {
            println("%s", item);
          }
        }
      }
    }
  }
}

class InfoCommand : Command {
  public override string name {
    get { return "info"; }
  }
  public override string usage {
    get { return "target|unit ![yellow]<item>![/]"; }
  }
  public override string description {
    get { return "Get information about targets or units."; }
  }

  private static bool arg_terse;

  public const OptionEntry[] options = {
    {"terse", 't', 0, OptionArg.NONE, ref arg_terse, "Show terse output.", null},
  };

  public override void run(string[] args) {
    if (args.length != 2) {
      fail("Expected 2 arguments, got %d.", args.length);
    } else if (args[0] != "target" && args[0] != "unit") {
      fail("Expected 'target' or 'unit', got %s.", args[0]);
    }

    var dirname = args[0];
    map_storage(dirname, (name, path, _) => {
      if (name != args[1]) {
        return;
      }

      if (dirname == "target") {
        bool present;
        var target = Target.read(name, out present);
        assert(present);

        if (arg_terse) {
          println("name: %s", name);
          println("id: %s", target.id);
          print("units:");
          foreach (var unit in target.units) {
            print(" %s", unit.name);
          }
          blankln();
        } else {
          println("![yellow]Name:![/] %s", name);
          println("![yellow]Id:![/] %s", target.id);
          println("![yellow]Units:![/]");
          foreach (var unit in target.units) {
            println("  · ![cyan]%s![/]", unit.name);
          }
        }
      } else if (dirname == "unit") {
        string[] unit_ids = {path.get_basename()};
        var unit = read_units_from_ids(unit_ids)[0];
        var type = unit.type == UnitType.BASE ? "base" : "builder";

        if (arg_terse) {
          println("name: %s", name);
          println("id: %s", unit.storage.id);
          println("type: %s", type);
          println("rel: %s", unit.rel);
          println("path: %s", unit.path);

          if (unit.deps.length > 0) {
            print("deps:");
            foreach (var dep in unit.deps) {
              print(" %s", dep.name);
            }
            blankln();
          }

          if (unit.expected_props.length > 0) {
            print("properties:");
            foreach (var prop in unit.expected_props) {
              print(" %s", prop);
            }
            blankln();
          }

          if (unit.given_props.size > 0) {
            foreach (var entry in unit.given_props.entries) {
              println("property %s: %s", entry.key, entry.value);
            }
          }
        } else {
          var time = Time.gm(0);
          time.strptime(unit.rel, "%Y-%m-%dT%H:%M:%S");
          var dt = new DateTime.utc(time.year + 1900, time.month, time.day, time.hour,
                                    time.minute, time.second);

          var fmt = "%B %d, %Y %H:%M:%S";
          var rel_utc = dt.format(fmt);
          var rel_local = dt.to_local().format(fmt);
          var rel_tz_name = dt.to_local().format("%Z");
          var rel_tz_offset = dt.to_local().format("%z");

          println("![yellow]Name:![/] %s", name);
          println("![yellow]Id:![/] %s", unit.storage.id);
          println("![yellow]Type:![/] %s", type);
          println("![yellow]Release: ![/]![cyan]UTC![/] %s +0000 / ![cyan]%s![/] %s %s",
                  rel_utc, rel_tz_name, rel_local, rel_tz_offset);
          println("![yellow]Unit path:![/] %s", unit.path);

          if (unit.deps.length > 0) {
            println("![yellow]Dependencies:![/]");
            foreach (var dep in unit.deps) {
              println("  · ![cyan]%s![/]", dep.name);
            }
          }

          if (unit.expected_props.length > 0) {
            println("![yellow]Properties:![/]");
            foreach (var prop in unit.expected_props) {
              print("  · ![cyan]%s![/]", prop);
              if (unit.given_props.has_key(prop)) {
                print("![cyan]: ![/]%s", unit.given_props[prop]);
              }
              blankln();
            }
          }
        }
      }

      Process.exit(0);
    });

    fail("Failed to find %s with name %s.", args[0], args[1]);
  }
}

class RemoveCommand : Command {
  public override string name {
    get { return "remove"; }
  }
  public override string usage {
    get { return "targets|units ![yellow]<items...>![/]"; }
  }
  public override string description {
    get { return "Remove targets or units."; }
  }

  public const OptionEntry[] options = {};

  public override void run(string[] args) {
    if (args.length == 1) {
      fail("Expected at least 2 arguments.");
    } else if (args[0] != "targets" && args[0] != "units") {
      fail("Expected 'targets' or 'units', got '%s'.", args[0]);
    }

    var dirname = args[0][0:args[0].length - 1];

    var to_remove = new HashSet<string>();
    foreach (var arg in args[1:args.length]) {
      to_remove.add(arg);
    }

    map_storage(dirname, (name, path, kf) => {
      if (name in to_remove) {
        println("Removing ![cyan]%s![/]...", name);
        SystemProvider.recursive_remove(path);
        to_remove.remove(name);
      }
    });

    foreach (var name in to_remove) {
      warn("Failed to locate %s: %s", dirname, name);
    }
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

      Command[] commands = {new TargetCommand(), new UpdateCommand(),
                            new ListCommand(), new InfoCommand(), new RemoveCommand()};
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

      println("  ![green]-%c --%-9s![/]%s", opt.short_name, opt.long_name,
              opt.description);
    }
  }

  private static void append_options(OptionEntry[] options) {
    foreach (var opt in options) {
      all_options += opt;
    }
  }

  public static int main(string[] args) {
    string[] pkexec_args = {"pkexec", SystemProvider.get_self().get_path()};
    foreach (var arg in args[1:args.length]) {
      pkexec_args += arg;
    }

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
      case "list":
        command = new ListCommand();
        append_options((OptionEntry[])ListCommand.options);
        break;
      case "info":
        command = new InfoCommand();
        append_options((OptionEntry[])InfoCommand.options);
        break;
      case "remove":
        command = new RemoveCommand();
        append_options((OptionEntry[])RemoveCommand.options);
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

    if (Posix.access("/", Posix.W_OK) == -1) {
      Posix.execvp("pkexec", pkexec_args);
      fail("pkexec execvp failed: %s", strerror(errno));
    }

    if (Linux.unshare(Linux.CloneFlags.NEWNS) == -1) {
      fail("Failed to unshare mount namespace: %s", strerror(errno));
    }

    SystemProvider.mount("none", "/", "",
                         Linux.MountFlags.PRIVATE | Linux.MountFlags.REC, "");
    SystemProvider.mkdir_p(File.new_for_path("/run/isolatekit/tmp"));
    SystemProvider.mkdir_p(File.new_for_path("/run/isolatekit/data"));
    SystemProvider.mount("tmpfs", "/run/isolatekit/tmp", "tmpfs", 0, "");
    SystemProvider.bindmount(SystemProvider.get_data_dir().get_path(),
                             "/run/isolatekit/data");

    Environment.set_variable("TMPDIR", "/run/isolatekit/tmp", true);

    command.run(args[2:args.length]);

    return 0;
  }
}
