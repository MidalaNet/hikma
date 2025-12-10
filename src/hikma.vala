using Gtk;
using Soup;
using Json;
using GLib;
using Gdk;
using Pango;
using Secret;
using WebKit;
using Hikma.API;
using Hikma.Crypto;
using Hikma.Core;
using Hikma.Persistence;

namespace Hikma.UI {
public class ChatWindow : Gtk.ApplicationWindow {
  private const int MAX_TURNS = 12;
  private const int MAX_MESSAGE_CHARS = 4000;

  private WebKit.WebView transcript_web;
  private TextView input;
  private ScrolledWindow input_scroll;
  private Overlay composer_overlay;
  private Button send_button;
  private Label send_label;
  private Spinner loader;
  private Label status_label;
  // No custom CSS provider; use default GTK appearance
  private ApiConfig config;
  private Soup.Session session;
  private bool sending = false;
  private Queue<Hikma.API.Message> history;
  private string crypto_key = "";
  private bool settings_ready = false;
  private Window modal_dialog;

  public ChatWindow(Gtk.Application app, ApiConfig config) {
    GLib.Object(application: app, title: "Hikma");
    this.config = config;

    // setup session
    session = new Soup.Session();
    session.timeout = (uint) (config.timeout_seconds);
    set_default_size(900, 680);
    set_resizable(true);

    set_titlebar(null); // allow window manager to provide decorations

    // resource path added in app; init history with system prompt
    history = new Queue<Hikma.API.Message>();
    history.push_tail(new Hikma.API.Message("system", config.system_prompt));

    load_saved_settings();
    ensure_crypto_key();
    load_context_cache();
    refresh_send_enabled();

    var root = new Box(Orientation.VERTICAL, 8);
    root.margin_top = 12;
    root.margin_bottom = 12;
    root.margin_start = 12;
    root.margin_end = 12;
    set_child(root);

    var toolbar = build_toolbar();
    root.append(toolbar);
    // Divider below toolbar only
    root.append(new Separator(Orientation.HORIZONTAL));

    transcript_web = new WebKit.WebView();
    string base_html = @"<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>
  <style>body{font-family:system-ui,sans-serif;margin:12px}.msg{margin:10px 0}.author{font-weight:600;margin-bottom:4px}.ai .content{background:#f6f7f9;border-radius:8px;padding:10px}</style>
  </head><body><div id='content'></div>
  <script>
  function append(author,text){var c=document.getElementById('content');var div=document.createElement('div');div.className='msg '+(author==='AI'?'ai':'you');var a=document.createElement('div');a.className='author';a.textContent=author+':';var cont=document.createElement('div');cont.className='content';cont.textContent=text;div.appendChild(a);div.appendChild(cont);c.appendChild(div);div.scrollIntoView({behavior:'instant',block:'end'});} 
  function clearAll(){ document.getElementById('content').innerHTML=''; }
  </script></body></html>";
    transcript_web.load_html(base_html, "resource:///");
    bool transcript_initialized = false;
    // Append history only once after initial load to avoid reload loops
    transcript_web.load_changed.connect((event) => {
      if (!transcript_initialized && event == WebKit.LoadEvent.FINISHED) {
        transcript_initialized = true;
        refresh_transcript_from_history();
      }
    });
    // Wrap transcript in a Frame to give a themed border (no label)
    var transcript_frame = new Frame(null);
    // Create white background overlay with padding
    var transcript_inner = new Box(Orientation.VERTICAL, 0);
    transcript_inner.set_margin_top(8);
    transcript_inner.set_margin_bottom(8);
    transcript_inner.set_margin_start(10);
    transcript_inner.set_margin_end(10);
    transcript_web.set_vexpand(true);
    transcript_inner.append(transcript_web);
    var transcript_overlay = create_white_overlay(transcript_inner);
    transcript_overlay.set_vexpand(true);
    transcript_frame.set_vexpand(true);
    transcript_frame.set_child(transcript_overlay);
    transcript_frame.set_margin_top(6);
    transcript_frame.set_margin_bottom(6);
    transcript_frame.set_margin_start(2);
    transcript_frame.set_margin_end(2);
    transcript_web.set_vexpand(true);
    root.append(transcript_frame);

    // Composer row: input on the left, send on the right.
    input = new TextView();
    input.wrap_mode = Gtk.WrapMode.WORD_CHAR;
    // Add inner spacing between text and frame
    input.set_margin_top(6);
    // Increase bottom margin to avoid text touching the frame
    input.set_margin_bottom(10);
    input.set_margin_start(8);
    input.set_margin_end(8);
    
    var key_controller = new EventControllerKey();
    key_controller.key_pressed.connect(on_input_key_press);
    input.add_controller(key_controller);
    input.buffer.changed.connect(() => refresh_send_enabled());

    input_scroll = new ScrolledWindow();
    input_scroll.set_child(input);
    input_scroll.set_hexpand(true);

    loader = new Spinner();
    
    loader.visible = false;
    loader.hexpand = false;

    send_button = new Button();
    send_label = new Label("Send");
    
    var send_icon = new Image.from_icon_name("mail-send-symbolic");
    
    var send_box = new Box(Orientation.HORIZONTAL, 6);
    send_box.append(send_icon);
    send_box.append(send_label);
    send_button.set_child(send_box);
    send_button.clicked.connect(on_send_clicked);
    // Use natural button height per GTK theme
    send_button.set_size_request(-1, -1);
    

    var composer_row = new Box(Orientation.HORIZONTAL, 8);
    composer_row.set_homogeneous(false);
    composer_row.margin_top = 6;
    composer_row.margin_bottom = 0;
    composer_row.margin_start = 2;
    composer_row.margin_end = 2;
    // Wrap composer in a Frame for a themed border (no label)
    var composer_frame = new Frame(null);
    composer_frame.set_vexpand(false);
    // Create white background overlay with padding
    var composer_inner = new Box(Orientation.VERTICAL, 0);
    composer_inner.set_margin_top(6);
    composer_inner.set_margin_bottom(6);
    composer_inner.set_margin_start(8);
    composer_inner.set_margin_end(8);
    composer_inner.set_hexpand(true);
    // Put only the input inside the framed area
    input_scroll.set_hexpand(true);
    input_scroll.set_min_content_height(48);
    composer_inner.append(input_scroll);
    composer_overlay = create_white_overlay(composer_inner);
    composer_overlay.set_vexpand(false);
    composer_overlay.set_hexpand(true);
    composer_overlay.set_size_request(-1, -1);
    composer_frame.set_child(composer_overlay);
    composer_frame.set_hexpand(true);
    composer_frame.set_margin_top(6);
    composer_frame.set_margin_bottom(6);
    composer_frame.set_margin_start(2);
    composer_frame.set_margin_end(2);
    // Row: frame (with input) + send + loader
    composer_row.append(composer_frame);
    // Visually align the button with the input
    send_button.set_margin_top(4);
    send_button.set_margin_bottom(4);
    composer_row.append(send_button);
    composer_row.append(loader);
    root.append(composer_row);
    refresh_send_enabled();

    // Divider above status for visual separation
    root.append(new Separator(Orientation.HORIZONTAL));
    status_label = new Label("Ready");
    
    status_label.halign = Align.START;
    status_label.margin_top = 4;
    status_label.margin_bottom = 2;
    root.append(status_label);

    present();
    input.grab_focus();
    // Align input frame height to the natural Send button height
    GLib.Idle.add(() => { sync_compose_heights(); return false; });
    prompt_for_pin_if_needed();
  }

  private void sync_compose_heights() {
    int btn_h = send_button.get_allocated_height();
    if (btn_h <= 0) return;
    // Match frame height to button and adjust input area accordingly
    composer_overlay.set_size_request(-1, btn_h);
    // Account for inner margins in the TextView so text is comfortable
    int inner_margins = 6 + 10; // top + bottom margins set on input
    int input_target = btn_h - inner_margins;
    if (input_target < 24) {
      input_target = 24;
    }
    input_scroll.set_min_content_height(input_target);
  }

  private Widget build_toolbar() {
    var bar = new Box(Orientation.HORIZONTAL, 8);
    bar.set_margin_bottom(6);
    var settings_btn = make_tool("emblem-system-symbolic", "Settings");
    settings_btn.clicked.connect(show_settings_dialog);
    var about_btn = make_tool("help-about-symbolic", "About");
    about_btn.clicked.connect(show_about_dialog);
    bar.append(settings_btn);
    bar.append(about_btn);
    return bar;
  }

  private Button make_tool(string icon, string tooltip) {
    var btn = new Button();
    
    var img = new Image.from_icon_name(icon);
    img.set_pixel_size(20);
    btn.set_child(img);
    btn.set_tooltip_text(tooltip);
    return btn;
  }

  private void add_row(Grid grid, ref int row, string label_text, Widget widget) {
    var lbl = new Label(label_text);
    lbl.halign = Align.START;
    grid.attach(lbl, 0, row, 1, 1);
    Entry? entry_widget = widget as Entry;
    if (entry_widget != null) {
      entry_widget.hexpand = true;
    }
    PasswordEntry? pass_widget = widget as PasswordEntry;
    if (pass_widget != null) {
      pass_widget.hexpand = true;
    }
    TextView? txt_widget = widget as TextView;
    if (txt_widget != null) {
      txt_widget.hexpand = true;
    }
    grid.attach(widget, 1, row, 1, 1);
    row++;
  }

  private void show_about_dialog() {
    var dialog = new Window();
    dialog.set_title("About Hikma");
    dialog.set_transient_for(this);
    dialog.set_modal(true);
    dialog.set_default_size(380, 260);
    var box = new Box(Orientation.VERTICAL, 10);
    box.set_margin_top(18);
    box.set_margin_bottom(18);
    box.set_margin_start(18);
    box.set_margin_end(18);
    dialog.set_child(box);
    box.set_spacing(10);

    var logo = new Image.from_resource("/net/midala/hikma/icons/hicolor/scalable/apps/net.midala.hikma.svg");
    logo.set_pixel_size(64);
    var title = new Label("<b>Hikma %s</b>".printf(Hikma.Config.APP_VERSION));
    title.use_markup = true;
    title.halign = Align.START;
    var subtitle = new Label("GTK4 chat client for OpenAI-compatible APIs, tested with llama-server and Bearer API key auth.");
    subtitle.halign = Align.START;
    subtitle.wrap = true;

    var tech = new Label("Built in Vala with GTK4, libsoup 3, json-glib, and libsecret to keep PIN-protected settings encrypted on disk.");
    tech.wrap = true;
    tech.halign = Align.START;

    var system = new Label(get_system_info());
    system.wrap = true;
    system.halign = Align.START;

    var close_btn = new Button.with_label("Close");
    
    close_btn.halign = Align.END;
    modal_dialog = dialog;
    close_btn.clicked.connect(on_modal_close_clicked);

    box.append(logo);
    box.append(title);
    box.append(subtitle);
    box.append(tech);
    box.append(system);
    box.append(close_btn);
    dialog.present();
  }

  private void show_settings_dialog() {
    var dialog = new Window();
    dialog.set_title("Settings");
    dialog.set_transient_for(this);
    dialog.set_modal(true);
    dialog.set_default_size(520, 480);
    
    var box = new Box(Orientation.VERTICAL, 16);
    box.set_margin_top(14);
    box.set_margin_bottom(14);
    box.set_margin_start(14);
    box.set_margin_end(14);
    dialog.set_child(box);
    box.set_spacing(16);

    // Scrollable content so action buttons remain visible
    var scroll = new ScrolledWindow();
    scroll.set_vexpand(true);
    box.append(scroll);

    var content = new Box(Orientation.VERTICAL, 12);
    scroll.set_child(content);

    var frame = new Frame(null);
    
    frame.set_margin_bottom(12);
    content.append(frame);

    var grid = new Grid();
    grid.set_row_spacing(10);
    grid.set_column_spacing(10);
    grid.set_margin_top(18);
    grid.set_margin_bottom(18);
    grid.set_margin_start(18);
    grid.set_margin_end(18);
    
    frame.set_child(grid);

    int row = 0;

    var endpoint_entry = new Entry();
    endpoint_entry.text = config.endpoint;
    add_row(grid, ref row, "API URL", endpoint_entry);

    var api_key_entry = new PasswordEntry();
    api_key_entry.text = config.api_key;
    api_key_entry.placeholder_text = "Bearer token (sk-...)";
    add_row(grid, ref row, "API Key", api_key_entry);

    var model_entry = new Entry();
    model_entry.text = config.model;
    add_row(grid, ref row, "Model", model_entry);

    var timeout_entry = new Entry();
    timeout_entry.text = "%u".printf(config.timeout_seconds);
    add_row(grid, ref row, "Timeout (s)", timeout_entry);

    var pin_entry = new PasswordEntry();
    pin_entry.placeholder_text = "4+ digit PIN to unlock settings";
    add_row(grid, ref row, "PIN", pin_entry);

    var prompt_view = new TextView();
    prompt_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR);
    prompt_view.buffer.set_text(config.system_prompt, -1);
    prompt_view.set_size_request(-1, 120);
    add_row(grid, ref row, "System prompt", prompt_view);

    // Action row pinned at bottom
    var actions = new Box(Orientation.HORIZONTAL, 10);
    actions.set_margin_top(12);
    actions.set_margin_bottom(6);
    actions.set_margin_start(4);
    actions.set_margin_end(4);
    var spacer = new Label("");
    spacer.hexpand = true;
    actions.append(spacer);

    var cancel_btn = create_icon_button("Cancel", "window-close-symbolic");
    modal_dialog = dialog;
    cancel_btn.clicked.connect(on_modal_close_clicked);
    actions.append(cancel_btn);
    var save_btn = create_icon_button("Save", "document-save-symbolic");
    save_btn.clicked.connect(() => on_settings_save_clicked(dialog, endpoint_entry, api_key_entry, model_entry, timeout_entry, pin_entry, prompt_view));
    actions.append(save_btn);

    box.append(actions);
    dialog.present();

  }

  private void on_settings_save_clicked(Window dialog, Entry endpoint_entry, PasswordEntry api_key_entry, Entry model_entry, Entry timeout_entry, PasswordEntry pin_entry, TextView prompt_view) {
    string endpoint = endpoint_entry.text.strip();
    string api_key = api_key_entry.text.strip();
    string model = model_entry.text.strip();
    string timeout_txt = timeout_entry.text.strip();
    string pin = pin_entry.text.strip();

    TextIter ps, pe;
    prompt_view.buffer.get_bounds(out ps, out pe);
    string system_prompt = prompt_view.buffer.get_text(ps, pe, false).strip();

    uint timeout_val = parse_timeout_value(timeout_txt, config.timeout_seconds);

    if (pin.length < 4) {
      set_status("PIN must be at least 4 digits", true);
      return;
    }

    Environment.set_variable("HIKMA_API_URL", endpoint, true);
    Environment.set_variable("HIKMA_API_KEY", api_key, true);
    if (model.length > 0) {
      Environment.set_variable("HIKMA_MODEL", model, true);
    }
    Environment.set_variable("HIKMA_TIMEOUT", "%u".printf(timeout_val), true);
    Environment.set_variable("HIKMA_SYSTEM_PROMPT", system_prompt, true);

    store_crypto_key(pin);

    config.apply_settings(endpoint, model.length > 0 ? model : config.model, api_key, timeout_val, system_prompt);
    session.timeout = timeout_val;

    history = new Queue<Hikma.API.Message>();
    history.push_tail(new Hikma.API.Message("system", config.system_prompt));
    save_settings_to_disk();
    ensure_crypto_key();
    refresh_send_enabled();
    dialog.set_visible(false);
  }

  private Button create_icon_button(string text, string icon_name) {
    var btn = new Button();
    var icon = new Image.from_icon_name(icon_name);
    icon.set_pixel_size(16);
    var lbl = new Label(text);
    var hbox = new Box(Orientation.HORIZONTAL, 6);
    hbox.append(icon);
    hbox.append(lbl);
    btn.set_child(hbox);
    return btn;
  }

  // No custom CSS; rely on GTK theme defaults

  // Create an overlay that paints a solid white background behind the given child
  private Overlay create_white_overlay(Widget child) {
    var overlay = new Overlay();
    // Background as main child (behind)
    var bg = new DrawingArea();
    bg.set_hexpand(true);
    bg.set_vexpand(true);
    bg.set_draw_func((area, ctx, width, height) => {
      ctx.set_source_rgb(1.0, 1.0, 1.0);
      ctx.rectangle(0, 0, width, height);
      ctx.fill();
    });
    bg.set_can_target(false);
    overlay.set_child(bg);
    // Foreground content on top
    overlay.add_overlay(child);
    return overlay;
  }

  private bool on_input_key_press(EventControllerKey controller, uint keyval, uint keycode, Gdk.ModifierType state) {
    if (keyval == Key.Return && (state & ModifierType.SHIFT_MASK) == 0) {
      on_send_clicked();
      return true; // consume Enter to avoid inserting newline
    }
    return false; // allow Shift+Enter (new lines) and other keys
  }

  private void on_send_clicked() {
    TextIter start;
    TextIter end;
    input.buffer.get_start_iter(out start);
    input.buffer.get_end_iter(out end);
    string user_text = input.buffer.get_text(start, end, false).strip();
    if (user_text.length == 0) {
      return;
    }
    if (user_text.length > MAX_MESSAGE_CHARS) {
      set_status("Message too long (max %d chars)".printf(MAX_MESSAGE_CHARS), true);
      return;
    }

    if (!config.has_credentials()) {
      append_line("Error", "Set HIKMA_API_KEY before sending.");
      return;
    }

    append_line("You", user_text);
    add_message("user", user_text);
    input.buffer.set_text("");
    input.grab_focus();
    send_message_async.begin();
  }

  private void set_sending(bool active) {
    sending = active;
    send_label.label = active ? "Sending..." : "Send";
    loader.visible = active;
    if (active) {
      loader.start();
    } else {
      loader.stop();
    }
    set_status(active ? "Sending..." : "Ready", false);
    refresh_send_enabled();
  }

  private void append_line(string author, string text) {
    if (transcript_web != null) {
      string js = "append(" + js_escape(author) + "," + js_escape(text) + ")";
      transcript_web.evaluate_javascript.begin(js, -1, null, null, null, (obj, res) => {
        try { ((WebKit.WebView) obj).evaluate_javascript.end(res); } catch (GLib.Error e) {}
      });
    }
  }


  private Soup.Message build_request() {
    var svc = new ChatService();
    return svc.build_request(config, history);
  }

  private string bytes_to_string(Bytes bytes) {
    var svc = new ChatService();
    return svc.bytes_to_string(bytes);
  }

  private string esc_html(string s) {
    return s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&#39;");
  }

  private string js_escape(string s) {
    string esc = s.replace("\\", "\\\\")
                  .replace("'", "\\'")
                  .replace("\n", "\\n")
                  .replace("\r", "\\r")
                  .replace("\t", "\\t");
    esc = esc.replace("</", "<\\/");
    return "'" + esc + "'";
  }

  private async void send_message_async() {
    if (sending) {
      return;
    }
    set_sending(true);
    set_status("Sending...", false);

    var message = build_request();
    try {
      Bytes response = yield session.send_and_read_async(message, Priority.DEFAULT, null);
      if (message.get_status() != Soup.Status.OK) {
        string msg = "HTTP " + message.get_status().to_string() + ": " + message.get_reason_phrase();
        append_line("Server", msg);
        set_status("HTTP error", true);
      } else {
        string response_text = bytes_to_string(response);
        try {
          var svc = new ChatService();
          string reply = svc.extract_reply(response_text);
          append_line("AI", reply);
          add_message("assistant", reply);
          save_context_cache();
          set_status("Reply received", false);
        } catch (GLib.Error parse_error) {
          string msg = "Parsing JSON: " + parse_error.message;
          append_line("Error", msg);
          append_line("Debug", response_text);
          set_status("Error: " + msg, true);
        }
      }
    } catch (GLib.Error e) {
      string msg = "Request failed: " + e.message;
      append_line("Error", msg);
      set_status("Network error", true);
    }

    set_sending(false);
    set_status("Ready", false);
  }

  private void add_message(string role, string content) {
    history.push_tail(new Hikma.API.Message(role, content));
    int max_entries = 1 + (MAX_TURNS * 2);
    while ((int) history.get_length() > max_entries && history.get_length() > 1) {
      // preserve system message at head
      Hikma.API.Message? head = history.pop_head();
      if (head != null && head.role == "system") {
        history.push_head(head);
        if (history.get_length() > 1) {
          history.pop_head();
        }
      }
    }
    save_context_cache();
  }

  private void save_context_cache() {
    if (crypto_key.strip().length == 0) return;
    var store = new Store();
    try {
      store.save_context(history, crypto_key);
      set_status("Context saved", false);
    } catch (GLib.Error e) { }
  }

  private void load_context_cache() {
    if (crypto_key.strip().length == 0) {
      set_status("Set PIN to restore chat history", true);
      return;
    }
    var store = new Store();
    string sys_prompt = config.system_prompt;
    if (store.load_context(ref history, crypto_key, sys_prompt)) {
      set_status("Chat history restored", false);
    } else {
      set_status("No saved chat history", false);
    }
  }

  private void refresh_transcript_from_history() {
    if (transcript_web == null) return;
    uint len = history.get_length();
    uint shown = 0;
    var roles = new GLib.List<string>();
    var texts = new GLib.List<string>();
    for (uint i = 0; i < len; i++) {
      Hikma.API.Message? m = history.peek_nth(i);
      if (m == null) continue;
      if (m.role == "system") continue;
      roles.append(m.role);
      texts.append(m.content);
      shown++;
    }
    // Render history in plain text by regenerating the page
    var inner = new GLib.StringBuilder();
    uint n = 0;
    while (true) {
      string? r = roles.nth_data(n);
      string? t = texts.nth_data(n);
      if (r == null || t == null) break;
      string author = (r == "assistant") ? "AI" : (r == "user" ? "You" : r);
      string klass = author == "AI" ? "ai" : "you";
      inner.append("<div class='msg " + klass + "'>");
      inner.append("<div class='author'>" + esc_html(author) + ":</div>");
      inner.append("<div class='content'>" + esc_html(t) + "</div>");
      inner.append("</div>");
      n++;
    }
    string html = @"<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>
<style>body{font-family:system-ui,sans-serif;margin:12px}.msg{margin:10px 0}.author{font-weight:600;margin-bottom:4px}.ai .content{background:#f6f7f9;border-radius:8px;padding:10px}</style></head><body><div id='content'>" + inner.str + @"</div>
<script>function append(author,text){var c=document.getElementById('content');var div=document.createElement('div');div.className='msg '+(author==='AI'?'ai':'you');var a=document.createElement('div');a.className='author';a.textContent=author+':';var cont=document.createElement('div');cont.className='content';cont.textContent=text;div.appendChild(a);div.appendChild(cont);c.appendChild(div);div.scrollIntoView({behavior:'instant',block:'end'});} function clearAll(){ document.getElementById('content').innerHTML=''; }</script>
</body></html>";
    transcript_web.load_html(html, "resource:///");
    if (shown == 0) {
      set_status("No chat history to display", false);
    } else {
      set_status("Chat history loaded", false);
    }
  }

  private void set_status(string text, bool is_error = false) {
    if (status_label != null) {
      status_label.label = text;
      // no style classes; default GTK styling
    }
  }

  private void refresh_send_enabled() {
    if (send_button == null) {
      return;
    }
    int len = get_input_length();
    bool within_limit = len <= MAX_MESSAGE_CHARS;
    bool enable = settings_ready && !sending && config.has_credentials() && crypto_key.strip().length > 0 && within_limit;
    send_button.set_tooltip_text(within_limit ? null : "Text too long (max %d chars)".printf(MAX_MESSAGE_CHARS));
    send_button.sensitive = enable;
  }

  private int get_input_length() {
    if (input == null) return 0;
    TextIter s, e;
    input.buffer.get_start_iter(out s);
    input.buffer.get_end_iter(out e);
    string txt = input.buffer.get_text(s, e, false);
    return (int) txt.length;
  }

  private void ensure_crypto_key() {
    if (crypto_key.strip().length == 0) {
      set_status("Set PIN in Settings to unlock sending", true);
      settings_ready = false;
      refresh_send_enabled();
      return;
    }
    settings_ready = config.has_credentials();
    refresh_send_enabled();
  }

  // No TextBuffer tags: Markdown rendered in WebView

  private string get_system_info() {
    string os_name = "Unknown OS";
    string os_ver = "";
    string kernel = "";

    // Try /etc/os-release
    string contents;
    size_t len;
    try {
      if (FileUtils.get_contents("/etc/os-release", out contents, out len)) {
        foreach (string raw in contents.split("\n")) {
          string line = raw.strip();
          if (line.has_prefix("NAME=")) {
            string val = line.substring(5).strip();
            if (val.length > 1 && val.has_prefix("\"") && val.has_suffix("\"")) {
              val = val.substring(1, (int) (val.length - 2));
            }
            os_name = val;
          } else if (line.has_prefix("VERSION=")) {
            string val = line.substring(8).strip();
            if (val.length > 1 && val.has_prefix("\"") && val.has_suffix("\"")) {
              val = val.substring(1, (int) (val.length - 2));
            }
            os_ver = val;
          }
        }
      }
    } catch (GLib.Error e) {
      // ignore and keep defaults
    }

    // Kernel via /proc
    string kcontents;
    size_t klen;
    try {
      if (FileUtils.get_contents("/proc/sys/kernel/osrelease", out kcontents, out klen)) {
        kernel = kcontents.strip();
      }
    } catch (GLib.Error e) {
      // ignore
    }

    string gtk_ver = "%u.%u.%u".printf(Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version());
    string soup_ver = "%u.%u.%u".printf(Soup.MAJOR_VERSION, Soup.MINOR_VERSION, Soup.MICRO_VERSION);

    var parts = new StringBuilder();
    parts.append("OS: %s %s\n".printf(os_name, os_ver));
    parts.append("Kernel: %s\n".printf(kernel));
    parts.append("GTK: %s\n".printf(gtk_ver));
    parts.append("libsoup: %s".printf(soup_ver));
    return parts.str;
  }

  private uint parse_timeout_value(string value, uint fallback) {
      int parsed;
      if (int.try_parse(value, out parsed) && parsed > 0) {
        return (uint) parsed;
      }
    return fallback;
  }

  private void load_saved_settings() {
    if (crypto_key.strip().length == 0) {
      set_status("Set a PIN to load saved settings", true);
      settings_ready = false;
      return;
    }
    var store = new Store();
    bool has_creds;
    if (store.load_settings_encrypted(config, crypto_key, out has_creds)) {
      session.timeout = (uint) config.timeout_seconds;
      history = new Queue<Hikma.API.Message>();
      history.push_tail(new Hikma.API.Message("system", config.system_prompt));
      settings_ready = has_creds;
      set_status("Settings loaded", false);
    } else {
      set_status("Failed to load settings", true);
      settings_ready = false;
    }
  }

  private void save_settings_to_disk() {
    if (crypto_key.strip().length == 0) {
      set_status("Set PIN before saving settings", true);
      return;
    }
    try {
      var store = new Store();
      store.save_settings_encrypted(config, crypto_key);
      settings_ready = config.has_credentials();
      set_status("Settings saved", false);
    } catch (GLib.Error e) {
      set_status("Failed to save settings", true);
      settings_ready = false;
    }
    refresh_send_enabled();
  }

  private void store_crypto_key(string pin) {
    try {
      string derived = CryptoUtils.derive_key_from_pin(pin);
      var store = new Store();
      store.store_pin_hash(derived);
      crypto_key = derived;
    } catch (GLib.Error e) {
      set_status("Failed to store PIN: " + e.message, true);
    }
  }

  private string? get_stored_pin_hash() {
    try {
      var store = new Store();
      return store.get_pin_hash();
    } catch (GLib.Error e) {
      set_status("Keyring unavailable: " + e.message, true);
      return null;
    }
  }

  private bool settings_file_exists() {
    try {
      var store = new Store();
      return store.has_settings();
    } catch (GLib.Error e) {
      return false;
    }
  }

  private void prompt_for_pin_if_needed() {
    if (!settings_file_exists() || crypto_key.strip().length > 0) {
      return;
    }

    var dialog = new Window();
    dialog.set_title("Unlock Settings");
    dialog.set_transient_for(this);
    dialog.set_modal(true);
    dialog.set_default_size(320, 140);
    var box = new Box(Orientation.VERTICAL, 10);
    box.set_margin_top(12);
    box.set_margin_bottom(12);
    box.set_margin_start(12);
    box.set_margin_end(12);
    dialog.set_child(box);

    var info = new Label("Enter your PIN to unlock saved settings.");
    info.wrap = true;
    info.halign = Align.START;

    var pin_entry = new PasswordEntry();
    pin_entry.placeholder_text = "PIN";

    var actions = new Box(Orientation.HORIZONTAL, 8);
    var spacer = new Label("");
    spacer.hexpand = true;
    actions.append(spacer);
    var cancel = new Button.with_label("Cancel");
    modal_dialog = dialog;
    cancel.clicked.connect(on_modal_close_clicked);
    var ok = new Button.with_label("Unlock");
    ok.clicked.connect(() => on_pin_unlock_clicked(dialog, pin_entry));
    actions.append(cancel);
    actions.append(ok);

    box.append(info);
    box.append(pin_entry);
    box.append(actions);
    dialog.present();
  }

  private void on_pin_unlock_clicked(Window dialog, PasswordEntry pin_entry) {
    string pin = pin_entry.text.strip();
    if (pin.length < 4) {
      set_status("PIN must be at least 4 digits", true);
      return;
    }
    string derived = CryptoUtils.derive_key_from_pin(pin);
    string? stored_hash = get_stored_pin_hash();
    if (stored_hash != null && stored_hash.length > 0 && stored_hash != derived) {
      set_status("Wrong PIN", true);
      return;
    }
    crypto_key = derived;
    load_saved_settings();
    ensure_crypto_key();
    load_context_cache();
    refresh_transcript_from_history();
    dialog.set_visible(false);
  }

  private void on_modal_close_clicked() {
    if (modal_dialog != null) {
      modal_dialog.set_visible(false);
      modal_dialog = null;
    }
  }
}

// Message class is defined in api.vala

public class HikmaApp : Gtk.Application {
  private ApiConfig config;

  public HikmaApp() {
    GLib.Object(application_id: "net.midala.hikma", flags: ApplicationFlags.DEFAULT_FLAGS);
    config = ApiConfig.from_env();
  }

  protected override void activate() {
    // Attach icon resources once the display is available.
    var display = Display.get_default();
    if (display != null) {
      var theme = IconTheme.get_for_display(display);
      theme.add_resource_path("/net/midala/hikma/icons");
      theme.add_resource_path("/net/midala/hikma/icons/hicolor");
      Gtk.Window.set_default_icon_name("net.midala.hikma");
    }
    new ChatWindow(this, config);
  }
}

}

public static int main(string[] args) {
  return new Hikma.UI.HikmaApp().run(args);
}
