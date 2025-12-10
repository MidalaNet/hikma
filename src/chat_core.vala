using Gtk;
using Soup;
using Json;
using GLib;
using Hikma.API;

namespace Hikma.Core {
  public class ChatService : GLib.Object {
    private const string PLAIN_PREFIX = "Rule 1: Always use plain text only (no Markdown), and respond as a single paragraph. ";

    private string ensure_prefixed(string content) {
      if (content == null) return PLAIN_PREFIX;
      if (content.has_prefix(PLAIN_PREFIX)) return content; // avoid duplicating if already saved that way
      return PLAIN_PREFIX + content;
    }

    public Soup.Message build_request(ApiConfig config, Queue<Hikma.API.Message> history) {
      var builder = new Json.Builder();
      builder.begin_object();

      builder.set_member_name("model");
      builder.add_string_value(config.model);

      builder.set_member_name("temperature");
      builder.add_double_value(0.1);

      builder.set_member_name("chat_template_kwargs");
      builder.begin_object();
      builder.set_member_name("enable_thinking");
      builder.add_boolean_value(false);
      builder.end_object();

      builder.set_member_name("messages");
      builder.begin_array();
      uint len = history.get_length();
      for (uint i = 0; i < len; i++) {
        Hikma.API.Message? m = history.peek_nth(i);
        if (m == null) {
          continue;
        }
        builder.begin_object();
        builder.set_member_name("role");
        builder.add_string_value(m.role);
        builder.set_member_name("content");
        if (m.role == "system") {
          builder.add_string_value(ensure_prefixed(m.content));
        } else {
          builder.add_string_value(m.content);
        }
        builder.end_object();
      }
      builder.end_array();
      builder.end_object();

      var generator = new Json.Generator();
      generator.set_root(builder.get_root());
      string body = generator.to_data(null);

      var message = new Soup.Message("POST", config.endpoint);

      if (config.api_key.strip().length > 0) {
        message.request_headers.append("Authorization", "Bearer " + config.api_key);
      }
      var body_bytes = new Bytes((uint8[]) body.data);
      message.set_request_body_from_bytes("application/json", body_bytes);

      return message;
    }

    public string extract_reply(string response_text) throws GLib.Error {
      var parser = new Json.Parser();
      parser.load_from_data(response_text);
      var root = parser.get_root().get_object();
      if (!root.has_member("choices")) {
        return "Response missing 'choices' field.";
      }

      var choices = root.get_array_member("choices");
      if (choices.get_length() == 0) {
        return "No choices returned by server.";
      }

      var first = choices.get_object_element(0);
      if (first.has_member("message")) {
        var message_obj = first.get_object_member("message");
        if (message_obj.has_member("content")) {
          return message_obj.get_string_member("content");
        }
      }

      if (first.has_member("delta")) {
        var delta = first.get_object_member("delta");
        if (delta.has_member("content")) {
          return delta.get_string_member("content");
        }
      }

      return "Unrecognized response format.";
    }

    public string bytes_to_string(Bytes bytes) {
      size_t len = bytes.get_size();
      unowned uint8[] raw = bytes.get_data();
      uint8[] copy = new uint8[len + 1];
      for (size_t i = 0; i < len; i++) {
        copy[i] = raw[i];
      }
      copy[len] = 0;
      return (string) copy;
    }
  }
}
