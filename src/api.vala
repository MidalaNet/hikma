using GLib;
using Hikma.Crypto;

namespace Hikma.API {

public class ApiConfig {
  public string endpoint { get; private set; }
  public string api_key { get; private set; }
  public string model { get; private set; }
  public uint timeout_seconds { get; private set; }
  public string system_prompt { get; private set; }

  public static ApiConfig from_env() {
    var cfg = new ApiConfig();
    cfg.endpoint = Environment.get_variable("HIKMA_API_URL");
    cfg.api_key = Environment.get_variable("HIKMA_API_KEY")
      ?? Environment.get_variable("AI_API_KEY")
      ?? "";
    cfg.model = Environment.get_variable("HIKMA_MODEL") ?? "qwen";
    string base_prompt = Environment.get_variable("HIKMA_SYSTEM_PROMPT")
      ?? "You are a concise writing assistant. Produce clear, natural English without inventing facts or using non-standard words.";
    cfg.system_prompt = base_prompt;
    cfg.timeout_seconds = parse_timeout(Environment.get_variable("HIKMA_TIMEOUT")
      ?? Environment.get_variable("AI_TIMEOUT")
      ?? "600");
    return cfg;
  }

  public bool has_credentials() {
    return api_key.strip().length > 0;
  }

  public void apply_settings(string endpoint, string model, string api_key, uint timeout_seconds, string system_prompt) {
    this.endpoint = endpoint;
    this.model = model;
    this.api_key = api_key;
    this.timeout_seconds = timeout_seconds;
    this.system_prompt = system_prompt;
  }

  public GLib.Variant to_variant_encrypted(string key) {
    var dict = new GLib.VariantDict(null);
    dict.insert_value("endpoint", new GLib.Variant.string(CryptoUtils.encrypt_string(endpoint, key)));
    dict.insert_value("api_key", new GLib.Variant.string(CryptoUtils.encrypt_string(api_key, key)));
    dict.insert_value("model", new GLib.Variant.string(CryptoUtils.encrypt_string(model, key)));
    dict.insert_value("timeout", new GLib.Variant.string(CryptoUtils.encrypt_string("%u".printf(timeout_seconds), key)));
    dict.insert_value("system_prompt", new GLib.Variant.string(CryptoUtils.encrypt_string(system_prompt, key)));
    return dict.end();
  }

  public void apply_from_variant(GLib.Variant variant, string key) {
    if (variant == null || !variant.is_of_type(new GLib.VariantType("a{sv}"))) {
      return;
    }
    var dict = new GLib.VariantDict(variant);
    string endpoint_v = decrypt_from_dict(dict, "endpoint", key, endpoint ?? "");
    string api_key_v = decrypt_from_dict(dict, "api_key", key, api_key ?? "");
    string model_v = decrypt_from_dict(dict, "model", key, model ?? "qwen");
    string timeout_v = decrypt_from_dict(dict, "timeout", key, "%u".printf(timeout_seconds));
    string prompt_v = decrypt_from_dict(dict, "system_prompt", key, system_prompt ?? "");
    uint timeout_parsed = parse_timeout(timeout_v);
    apply_settings(endpoint_v, model_v, api_key_v, timeout_parsed, prompt_v);
  }

  private string decrypt_from_dict(GLib.VariantDict dict, string key_name, string key, string fallback) {
    GLib.Variant? v = dict.lookup_value(key_name, new GLib.VariantType("s"));
    if (v == null) return fallback ?? "";
    string cipher = v.get_string();
    return CryptoUtils.decrypt_string(cipher, key, fallback ?? "");
  }

  private static uint parse_timeout(string value) {
    uint result = 90;
      int parsed;
      if (int.try_parse(value, out parsed) && parsed > 0) {
        result = (uint) parsed;
      }
    return result;
  }
}

public class Message {
  public string role;
  public string content;

  public Message(string role, string content) {
    this.role = role;
    this.content = content;
  }
}

}
