using GLib;
using Secret;
using Json;
using Hikma.API;
using Hikma.Crypto;

namespace Hikma.Persistence {
  public class Store : GLib.Object {
    private string schema_name = "net.midala.hikma";

    private Secret.Schema get_schema() {
      return new Secret.Schema(
        schema_name,
        Secret.SchemaFlags.NONE,
        "purpose", Secret.SchemaAttributeType.STRING,
        null
      );
    }

    public void save_settings_encrypted(ApiConfig config, string crypto_key) throws GLib.Error {
      GLib.Variant variant = config.to_variant_encrypted(crypto_key);
      var bytes = variant.get_data_as_bytes();
      size_t len = bytes.get_size();
      unowned uint8[] raw = bytes.get_data();
      uint8[] copy = new uint8[len];
      for (size_t i = 0; i < len; i++) copy[i] = raw[i];
      string b64 = Base64.encode(copy);
      Secret.password_store_sync(
        get_schema(),
        Secret.COLLECTION_DEFAULT,
        "Hikma Settings",
        b64,
        null,
        "purpose", "hikma-settings"
      );
    }

    public bool load_settings_encrypted(ApiConfig config, string crypto_key, out bool has_credentials) {
      has_credentials = false;
      try {
        string? b64 = Secret.password_lookup_sync(get_schema(), null, "purpose", "hikma-settings");
        if (b64 == null || b64.strip().length == 0) return false;
        uint8[] data = Base64.decode(b64);
        var bytes = new Bytes(data);
        var variant = new GLib.Variant.from_bytes(new GLib.VariantType("a{sv}"), bytes, false);
        config.apply_from_variant(variant, crypto_key);
        has_credentials = config.has_credentials();
        return true;
      } catch (GLib.Error e) {
        return false;
      }
    }

    public void save_context(Queue<Hikma.API.Message> history, string crypto_key) throws GLib.Error {
      var builder = new Json.Builder();
      builder.begin_array();
      uint len = history.get_length();
      for (uint i = 0; i < len; i++) {
        Hikma.API.Message? m = history.peek_nth(i);
        if (m == null) continue;
        builder.begin_object();
        builder.set_member_name("role");
        builder.add_string_value(m.role);
        builder.set_member_name("content");
        builder.add_string_value(m.content);
        builder.end_object();
      }
      builder.end_array();
      var gen = new Json.Generator();
      gen.set_root(builder.get_root());
      string json = gen.to_data(null);
      string b64 = CryptoUtils.xor_b64_from_string(json, crypto_key);
      Secret.password_store_sync(
        get_schema(),
        Secret.COLLECTION_DEFAULT,
        "Hikma Context",
        b64,
        null,
        "purpose", "hikma-context"
      );
    }

    public bool load_context(ref Queue<Hikma.API.Message> history, string crypto_key, string system_prompt) {
      try {
        string? b64 = Secret.password_lookup_sync(get_schema(), null, "purpose", "hikma-context");
        if (b64 == null || b64.strip().length == 0) return false;
        string json = CryptoUtils.xor_b64_to_string(b64, crypto_key);
        var parser = new Json.Parser();
        parser.load_from_data(json);
        var arr = parser.get_root().get_array();
        history = new Queue<Hikma.API.Message>();
        history.push_tail(new Hikma.API.Message("system", system_prompt));
        for (uint i = 0; i < arr.get_length(); i++) {
          var obj = arr.get_object_element(i);
          string role = obj.get_string_member("role");
          string content = obj.get_string_member("content");
          if (role == "system") continue;
          history.push_tail(new Hikma.API.Message(role, content));
        }
        return true;
      } catch (GLib.Error e) {
        return false;
      }
    }

    public void store_pin_hash(string derived) throws GLib.Error {
      Secret.password_store_sync(
        get_schema(),
        Secret.COLLECTION_DEFAULT,
        "Hikma PIN",
        derived,
        null,
        "purpose", "hikma-crypto"
      );
    }

    public string? get_pin_hash() {
      try {
        return Secret.password_lookup_sync(get_schema(), null, "purpose", "hikma-crypto");
      } catch (GLib.Error e) {
        return null;
      }
    }

    public bool has_settings() {
      try {
        string? v = Secret.password_lookup_sync(get_schema(), null, "purpose", "hikma-settings");
        return v != null && v.strip().length > 0;
      } catch (GLib.Error e) {
        return false;
      }
    }
  }
}
