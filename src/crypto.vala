using GLib;

namespace Hikma.Crypto {

public class CryptoUtils {
  public static string encrypt_string(string plain, string key) {
    if (key == null || key.strip().length == 0) {
      return plain;
    }
    uint8[] data = (uint8[]) plain.data;
    uint8[] key_bytes = (uint8[]) key.data;
    uint8[] out_bytes = new uint8[data.length];
    for (int i = 0; i < data.length; i++) {
      out_bytes[i] = (uint8) (data[i] ^ key_bytes[i % key_bytes.length]);
    }
    return Base64.encode(out_bytes);
  }

  public static string decrypt_string(string cipher, string key, string fallback) {
    if (key == null || key.strip().length == 0) {
      return fallback;
    }
    uint8[] enc = Base64.decode(cipher);
    uint8[] key_bytes = (uint8[]) key.data;
    uint8[] out_bytes = new uint8[enc.length + 1];
    for (int i = 0; i < enc.length; i++) {
      out_bytes[i] = (uint8) (enc[i] ^ key_bytes[i % key_bytes.length]);
    }
    out_bytes[enc.length] = 0;
    return (string) out_bytes;
  }

  public static string derive_key_from_pin(string pin) {
    var checksum = new Checksum(ChecksumType.SHA256);
    checksum.update(pin.data, pin.length);
    return checksum.get_string();
  }

  public static string xor_b64_from_string(string text, string key) {
    uint8[] data = (uint8[]) text.data;
    uint8[] key_bytes = (uint8[]) key.data;
    uint8[] out_bytes = new uint8[data.length];
    for (int i = 0; i < data.length; i++) {
      out_bytes[i] = (uint8) (data[i] ^ key_bytes[i % key_bytes.length]);
    }
    return Base64.encode(out_bytes);
  }

  public static string xor_b64_to_string(string b64, string key) {
    uint8[] enc = Base64.decode(b64);
    uint8[] key_bytes = (uint8[]) key.data;
    uint8[] out_bytes = new uint8[enc.length + 1];
    for (int i = 0; i < enc.length; i++) {
      out_bytes[i] = (uint8) (enc[i] ^ key_bytes[i % key_bytes.length]);
    }
    out_bytes[enc.length] = 0;
    return (string) out_bytes;
  }
}

}
