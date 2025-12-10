project(
  'hikma',
  'vala',
  version: '0.1.7',
  default_options: [
    'warning_level=2',
    'werror=false'
  ]
)

gnome = import('gnome')

libsecret_dep = dependency('libsecret-1', required: true)
vala_args = []
vala_args += ['-D', 'HAVE_LIBSECRET']
vala_args += ['--disable-warnings']

subdir('src')

install_data(
  'src/hicolor/scalable/apps/net.midala.hikma.svg',
  install_dir: join_paths(get_option('datadir'), 'icons/hicolor/scalable/apps')
)
install_data(
  'src/hicolor/index.theme',
  install_dir: join_paths(get_option('datadir'), 'icons/hicolor')
)
