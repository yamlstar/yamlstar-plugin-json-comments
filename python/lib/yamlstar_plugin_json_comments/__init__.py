# Copyright 2026 yaml.org
# MIT License

"""Installed library paths for the YAMLStar JSON comments plugin."""

import os
from pathlib import Path
import sys


def _library_filename():
  if sys.platform == 'darwin':
    extension = 'dylib'
  elif sys.platform == 'linux' or sys.platform.startswith('freebsd'):
    extension = 'so'
  else:
    raise RuntimeError(
      "Unsupported platform '%s' for yamlstar-plugin-json-comments" %
      sys.platform)
  return 'libyamlstar-plugin-json-comments.%s' % extension


def library_path():
  """Return the absolute path to the installed plugin library."""
  path = Path(__file__).parent / 'lib' / _library_filename()
  if not path.is_file():
    raise RuntimeError('YAMLStar JSON comments library not found: %s' % path)
  return str(path.resolve())


def library_dir():
  """Return the absolute directory containing the plugin library."""
  return os.path.dirname(library_path())


def manifest_path():
  """Return the absolute path to the installed plugin manifest."""
  path = Path(__file__).parent / 'plugin.edn'
  if not path.is_file():
    raise RuntimeError('YAMLStar JSON comments manifest not found: %s' % path)
  return str(path.resolve())
