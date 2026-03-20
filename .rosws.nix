{ pkgs }:
let
  jazzyPrefixes = "${pkgs.rosPackages.jazzy.ament-cmake}:${pkgs.rosPackages.jazzy.ament-cmake-core}:${pkgs.rosPackages.jazzy.python-cmake-module}:${pkgs.rosPackages.jazzy.rmw}:${pkgs.rosPackages.jazzy.rosidl-default-generators}:${pkgs.rosPackages.jazzy.rosidl-runtime-c}:${pkgs.rosPackages.jazzy.rosidl-typesupport-c}:${pkgs.rosPackages.jazzy.rosidl-typesupport-interface}:${pkgs.rosPackages.jazzy.std-msgs}";
in
{
  shellHook = ''
    dedup_flags() {
        local var_name="$1"
        local current_value
        current_value="$(printenv "$var_name" 2>/dev/null || true)"

        if [ -z "$current_value" ]; then
            return
        fi

        # mkShell can accumulate repeated wrapper flags from propagated dev outputs.
        # Preserve the first occurrence of each complete flag entry, keeping
        # option/value pairs such as "-isystem <path>" intact.
        export "$var_name=$(
            printf '%s' "$current_value" \
                | tr ' ' '\n' \
                | awk '
                    function flush_entry(entry_key, entry_value) {
                        if (!(entry_key in seen)) {
                            seen[entry_key] = 1
                            print entry_value
                        }
                    }

                    BEGIN {
                        expects_value["-I"] = 1
                        expects_value["-L"] = 1
                        expects_value["-B"] = 1
                        expects_value["-include"] = 1
                        expects_value["-iquote"] = 1
                        expects_value["-idirafter"] = 1
                        expects_value["-isystem"] = 1
                        expects_value["-isysroot"] = 1
                        expects_value["-iframework"] = 1
                    }

                    NF == 0 {
                        next
                    }

                    pending_option != "" {
                        flush_entry(pending_option SUBSEP $0, pending_option " " $0)
                        pending_option = ""
                        next
                    }

                    {
                        if ($0 in expects_value) {
                            pending_option = $0
                            next
                        }

                        flush_entry($0, $0)
                    }

                    END {
                        if (pending_option != "") {
                            flush_entry(pending_option, pending_option)
                        }
                    }
                ' \
                | paste -sd ' ' -
        )"
    }

    dedup_flags NIX_CFLAGS_COMPILE
    dedup_flags NIX_CXXFLAGS_COMPILE
    dedup_flags NIX_LDFLAGS

    prepend_prefixes() {
        local var_name="$1"
        local existing_value

        existing_value="$(printenv "$var_name" 2>/dev/null || true)"
        if [ -n "$existing_value" ]; then
            export "$var_name=${jazzyPrefixes}:$existing_value"
        else
            export "$var_name=${jazzyPrefixes}"
        fi
    }

    # These Nix store package paths are usable as CMake prefixes, but
    # they are not setup prefixes because they don't ship local_setup.*.
    prepend_prefixes CMAKE_PREFIX_PATH

    setup_synthetic_ament_prefix() {
        local synthetic_prefix
        local source_prefixes
        local old_ifs="$IFS"
        local prefix
        local category_dir
        local resource
        local existing_value
        local filtered=""

        synthetic_prefix="$PWD/.nix-ament-prefix"
        mkdir -p "$synthetic_prefix/share/ament_index/resource_index"

        cat > "$synthetic_prefix/local_setup.sh" <<'EOF'
#!/usr/bin/env sh
EOF
        cat > "$synthetic_prefix/local_setup.bash" <<'EOF'
#!/usr/bin/env bash
EOF
        cat > "$synthetic_prefix/local_setup.zsh" <<'EOF'
#!/usr/bin/env zsh
EOF
        chmod +x \
            "$synthetic_prefix/local_setup.sh" \
            "$synthetic_prefix/local_setup.bash" \
            "$synthetic_prefix/local_setup.zsh"

        find "$synthetic_prefix/share/ament_index/resource_index" -mindepth 1 -delete

        source_prefixes="$(printenv CMAKE_PREFIX_PATH 2>/dev/null || true)"
        IFS=:
        for prefix in $source_prefixes; do
            if [ ! -d "$prefix/share/ament_index/resource_index" ]; then
                continue
            fi

            for category_dir in "$prefix"/share/ament_index/resource_index/*; do
                if [ ! -d "$category_dir" ]; then
                    continue
                fi

                mkdir -p "$synthetic_prefix/share/ament_index/resource_index/$(basename "$category_dir")"
                for resource in "$category_dir"/*; do
                    if [ ! -f "$resource" ]; then
                        continue
                    fi
                    ln -sf "$resource" \
                        "$synthetic_prefix/share/ament_index/resource_index/$(basename "$category_dir")/$(basename "$resource")"
                done
            done
        done
        IFS="$old_ifs"

        existing_value="$(printenv AMENT_PREFIX_PATH 2>/dev/null || true)"
        if [ -n "$existing_value" ]; then
            IFS=:
            for prefix in $existing_value; do
                if [ -f "$prefix/local_setup.sh" ] || [ -f "$prefix/local_setup.bash" ] || [ -f "$prefix/local_setup.zsh" ]; then
                    if [ -n "$filtered" ]; then
                        filtered="$filtered:$prefix"
                    else
                        filtered="$prefix"
                    fi
                fi
            done
            IFS="$old_ifs"
        fi

        if [ -n "$filtered" ]; then
            export AMENT_PREFIX_PATH="$synthetic_prefix:$filtered"
        else
            export AMENT_PREFIX_PATH="$synthetic_prefix"
        fi
    }

    setup_synthetic_ament_prefix
  '';
}
