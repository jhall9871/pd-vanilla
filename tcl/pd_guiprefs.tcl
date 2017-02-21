#
# Copyright (c) 1997-2009 Miller Puckette.
# Copyright (c) 2011 Yvan Volochine.
#(c) 2008 WordTech Communications LLC. License: standard Tcl license, http://www.tcl.tk/software/tcltk/license.html

package provide pd_guiprefs 0.1


namespace eval ::pd_guiprefs:: {
    namespace export init
    namespace export write_recentfiles
    namespace export update_recentfiles
}

# FIXME should these be globals ?
set ::recentfiles_key ""
set ::pd_guiprefs::domain ""


#################################################################
# global procedures
#################################################################
# ------------------------------------------------------------------------------
# init preferences
#
proc ::pd_guiprefs::init {} {
    switch -- $::windowingsystem {
        "aqua" {
            # osx has a "Open Recent" menu with 10 recent files (others have 5 inlined)
            set ::pd_guiprefs::domain org.puredata
            set ::recentfiles_key "NSRecentDocuments"
            set ::total_recentfiles 10

            # ------------------------------------------------------------------------------
            # osx: read a plist file
            #
            proc ::pd_guiprefs::get_config {adomain {akey} {arr false}} {
                if {![catch {exec defaults read $adomain $akey} conf]} {
                    if {$arr} {
                        set conf [plist_array_to_tcl_list $conf]
                    }
                } else {
                    # initialize NSRecentDocuments with an empty array
                    exec defaults write $adomain $akey -array
                    set conf {}
                }
                return $conf
            }
            # ------------------------------------------------------------------------------
            # osx: write configs to plist file
            # if $arr is true, we write an array
            #
            proc ::pd_guiprefs::write_config {data {adomain} {akey} {arr false}} {
                # FIXME empty and write again so we don't loose the order
                if {[catch {exec defaults write $adomain $akey -array} errorMsg]} {
                    ::pdwindow::error "write_config $akey: $errorMsg\n"
                }
                if {$arr} {
                    foreach filepath $data {
                        set escaped [escape_for_plist $filepath]
                        exec defaults write $adomain $akey -array-add "$escaped"
                    }
                } else {
                    set escaped [escape_for_plist $data]
                    exec defaults write $adomain $akey '$escaped'
                }

                # Disable window state saving by default for 10.7+ as there is a chance
                # pd will hang on start due to conflicting patch resources until the state
                # is purged. State saving will still work, it just has to be explicitly
                # asked for by holding the Option/Alt button when quitting via the File
                # menu or with the Cmd+Q key binding.
                exec defaults write $adomain NSQuitAlwaysKeepsWindows -bool false
                return
            }

        }
        "win32" {
            # windows uses registry
            set ::pd_guiprefs::domain "HKEY_CURRENT_USER\\Software\\Pure-Data"
            set ::recentfiles_key "RecentDocs"

            # ------------------------------------------------------------------------------
            # w32: read in the registry
            #
            proc ::pd_guiprefs::get_config {adomain {akey} {arr false}} {
                package require registry
                if {![catch {registry get $adomain $akey} conf]} {
                    return [expr {$conf}]
                }
                return {}
            }
            # ------------------------------------------------------------------------------
            # w32: write configs to registry
            # if $arr is true, we write an array
            #
            proc ::pd_guiprefs::write_config {data {adomain} {akey} {arr false}} {
                package require registry
                # FIXME: ugly
                if {$arr} {
                    if {[catch {registry set $adomain $akey $data multi_sz} errorMsg]} {
                        ::pdwindow::error "write_config $data $akey: $errorMsg\n"
                    }
                } else {
                    if {[catch {registry set $adomain $akey $data sz} errorMsg]} {
                        ::pdwindow::error "write_config $data $akey: $errorMsg\n"
                    }
                }
                return
            }

        }
        "x11" {
            set ::pd_guiprefs::domain pure-data
            set ::recentfiles_key "recentfiles"

            prepare_configdir

            # ------------------------------------------------------------------------------
            # linux: read a config file and return its lines splitted.
            #
            proc ::pd_guiprefs::get_config {adomain {akey} {arr false}} {
                return [::pd_guiprefs::get_config_file $adomain $akey $arr]
            }
            # ------------------------------------------------------------------------------
            # linux: write configs to USER_APP_CONFIG_DIR
            # $arr is true if the data needs to be written in an array
            #
            proc ::pd_guiprefs::write_config {data {adomain} {akey} {arr false}} {
                return [::pd_guiprefs::write_config_file $data $adomain $akey $arr]
            }
        }
    }
    # assign gui preferences
    # osx special case for arrays
    set arr [expr { $::windowingsystem eq "aqua" }]
    set ::recentfiles_list ""
    catch {set ::recentfiles_list [get_config $::pd_guiprefs::domain \
        $::recentfiles_key $arr]}
}

# ------------------------------------------------------------------------------
# read a config file and return its lines splitted.
#
proc ::pd_guiprefs::get_config_file {adomain {akey} {arr false}} {
    set filename [file join ${adomain} ${akey}.conf]
    set conf {}
    if {
        [file exists $filename] == 1
        && [file readable $filename]
    } {
        set fl [open $filename r]
        while {[gets $fl line] >= 0} {
            lappend conf $line
        }
        close $fl
    }
    return $conf
}
# ------------------------------------------------------------------------------
# write configs to USER_APP_CONFIG_DIR
# $arr is true if the data needs to be written in an array
#
proc ::pd_guiprefs::write_config_file {data {adomain} {akey} {arr false}} {
    # right now I (yvan) assume that data are just \n separated, i.e. no keys
    set data [join $data "\n"]
    set filename [file join ${adomain} ${akey}.conf]
    if {[catch {set fl [open $filename w]} errorMsg]} {
        ::pdwindow::error "write_config $data $akey: $errorMsg\n"
    } else {
        puts -nonewline $fl $data
        close $fl
    }
}

#################################################################
# main read/write procedures
#################################################################

## these are stubs that will be overwritten in ::pd_guiprefs::init()
proc ::pd_guiprefs::write_config {data {adomain} {akey} {arr false}} {
    ::pdwindow::error "::pd_guiprefs::write_config not implemented for $::windowingsystem\n"
}
proc ::pd_guiprefs::get_config {adomain {akey} {arr false}} {
    ::pdwindow::error "::pd_guiprefs::get_config not implemented for $::windowingsystem\n"
}

# simple API (with a default domain)
proc ::pd_guiprefs::write {key data {arr false} {domain {}}} {
    if {"" eq $domain} { set domain ${::pd_guiprefs::domain} }
    set result [::pd_guiprefs::write_config $data $domain $key $arr]
    return $result
}
proc ::pd_guiprefs::get {key {arr false} {domain {}}} {
    if {"" eq $domain} { set domain ${::pd_guiprefs::domain} }
    set result [::pd_guiprefs::get_config $domain $key $arr]
    return $result
}

#################################################################
# utils
#################################################################

# ------------------------------------------------------------------------------
# linux only! : look for pd config directory and create it if needed
#
proc ::pd_guiprefs::prepare_configdir {{domain pure-data}} {
    set confdir ""
    # linux uses ~/.config/pure-data dir
    if {[info exists ::env(XDG_CONFIG_HOME)]} {
        set confdir $::env(XDG_CONFIG_HOME)
    }
    if {"" eq ${confdir}} {
        set confdir [file join ~ .config]
    }
    set configfile [file join $confdir $domain]
    set ::pd_guiprefs::domain $configfile

    if { [catch {
        if {[file isdirectory $configfile] != 1} {
            file mkdir $configfile
            ::pdwindow::debug "$::pd_guiprefs::domain was created.\n"
            }
    }]} {
        ::pdwindow::error "$::pd_guiprefs::domain was *NOT* created.\n"
    }
}

# ------------------------------------------------------------------------------
# osx: handles arrays in plist files (thanks hc)
#
proc ::pd_guiprefs::plist_array_to_tcl_list {arr} {
    set result {}
    set filelist $arr
    regsub -all -- {("?),\s+("?)} $filelist {\1 \2} filelist
    regsub -all -- {\n} $filelist {} filelist
    regsub -all -- {^\(} $filelist {} filelist
    regsub -all -- {\)$} $filelist {} filelist
    regsub -line -- {^'(.*)'$} $filelist {\1} filelist
    regsub -all -- {\\\\U} $filelist {\\u} filelist

    foreach file $filelist {
        set filename [regsub -- {,$} $file {}]
        lappend result $filename
    }
    return $result
}

# the Mac OS X 'defaults' command uses single quotes to quote things,
# so they need to be escaped
proc ::pd_guiprefs::escape_for_plist {str} {
    return \"[regsub -all -- {"} $str {\\"}]\"
}


#################################################################
# recent files
#################################################################


# ------------------------------------------------------------------------------
# write recent files
#
proc ::pd_guiprefs::write_recentfiles {} {
    write_config $::recentfiles_list $::pd_guiprefs::domain $::recentfiles_key true
}

# ------------------------------------------------------------------------------
# this is called when opening a document (wheredoesthisshouldgo.tcl)
#
proc ::pd_guiprefs::update_recentfiles {afile} {
    # remove duplicates first
    set index [lsearch -exact $::recentfiles_list $afile]
    set ::recentfiles_list [lreplace $::recentfiles_list $index $index]
    # insert new one in the beginning and crop the list
    set ::recentfiles_list [linsert $::recentfiles_list 0 $afile]
    set ::recentfiles_list [lrange $::recentfiles_list 0 $::total_recentfiles]
    ::pd_menus::update_recentfiles_menu
}
