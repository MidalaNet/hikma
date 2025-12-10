resources = gnome.compile_resources(
  'hikma-resources',
  'resources.xml',
  c_name: 'hikma_resources'
)

conf = configuration_data()
conf.set('APP_VERSION', meson.project_version())
version_file = configure_file(
  input: 'version.vala.in',
  output: 'version.vala',
  configuration: conf
)

vala_args = [
  '--debug',
  '--gresources=' + join_paths(meson.current_source_dir(), 'resources.xml'),
  '--gresourcesdir=' + join_paths(meson.current_build_dir(), '..', 'src'),
]

sources = [
  'hikma.vala',
  'api.vala',
  'crypto.vala',
  'chat_core.vala',
  'persist.vala',
  version_file,
]

# Include compiled resources (icons, etc.) in the executable
sources += resources

webkit_dep = dependency('webkitgtk-6.0', required: true)

executable(
  'hikma',
  sources,
  dependencies: [
    dependency('gtk4', version: '>=4.6'),
    dependency('libsoup-3.0'),
    dependency('json-glib-1.0'),
    dependency('gio-2.0'),
    webkit_dep,
  ] + (libsecret_dep.found() ? [libsecret_dep] : []),
  vala_args: vala_args,
  c_args: [
    '-Wno-cast-function-type',
    '-Wno-discarded-qualifiers',
    '-Wno-unused-parameter',
    '-Wno-unused-but-set-variable',
    '-Wno-unused-function'
  ],
  install: true
)
