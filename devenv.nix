{
  pkgs,
  lib,
  config,
  ...
}:
{
  # https://devenv.sh/languages/
  languages.rust.enable = true;

  # https://devenv.sh/reference/options/#claude
  claude.code.enable = true;

  # See full reference at https://devenv.sh/reference/options/
}

