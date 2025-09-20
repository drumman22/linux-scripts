# by drumman22
# --wraps='paru -Syu --noconfirm && flatpak update -y' 
function fupdate --description 'Full system update (Pacman, AUR, Flatpak)'
    function _help
        echo "fupdate - Full system update (Pacman/AUR + Flatpak)"
        echo ""
        echo "Usage:"
        echo "  fupdate [flags] [paru options]"
        echo ""
        echo "Flags:"
        echo "  --check, -c      Show number of updates only (dry run)"
        echo "  --list,  -l      List packages that would be updated"
        echo "  --help,  -h      Show this help message"
    end

    set -g paru_updates
    set -g flatpak_updates

    # _get_updates <command> <command_name>
    function _get_updates
        set updates (eval $argv[1])
        if test (count $updates) -gt 0
            if _is_flatpak $argv[2]
                set -g flatpak_updates $updates
            else
                set -g paru_updates $updates
            end
        end
    end

    function _echo_updates
        set packages
        if _is_flatpak $argv[2]
            set packages $flatpak_updates
        else
            set packages $paru_updates
        end
        set count (count $packages)
        if test $count -eq 0
            return # return if there are no upated packages
        end
        
        if test $argv[1] = "count"
            echo "$argv[2] updates: $count packages"
        else if test $argv[1] = "list"
            echo "$argv[2] packages: $packages"
        end 
    end

    # Helper functions
    function _is_flatpak
        test $argv[1] = "Flatpak"
    end

    function _run_echo_updates
        _echo_updates $argv[1] "Pacman/AUR"
        _echo_updates $argv[1] "Flatpak"
    end

    # Handle flags
    set flags --help -h --check -c --list -l -cl
    if set -q argv[1] # Does first argument exist
        if contains -- $argv[1] $flags # If valid flag
            if contains -- $argv[1] "--help" "-h"
                _help
                return
            end

            _get_updates "paru -Qu" "Pacman/AUR"
            _get_updates "flatpak remote-ls --updates" "Flatpak"

            for arg in $argv
                if contains -- $arg "--check" "-c" "-cl"
                    _run_echo_updates "count"
                end
                
                if contains -- $arg "--list" "-l" "-cl"
                    _run_echo_updates "list"
                end
            end
            
            # If there are updates, ask user if they want to update
            set total_count (math (count $paru_updates) + (count $flatpak_updates))
            if test $total_count -gt 0
                read -P "There are $total_count updates available. Install? (y/n): " user_input
                if string match -qi "y" $user_input
                    fupdate
                end
            else
                echo "There are 0 updates available"
            end
        else
            echo "fupdate: $argv[1]: unknown flag"
        end
        
        return
    end

    # Main install commands
    echo "==> Updating Pacman/AUR + Flatpak packages..."
    paru -Syu --noconfirm $argv
    
    echo "==> Updating Flatpak packages..."
    flatpak update -y
    
    echo "==> Updating finished!"
end
