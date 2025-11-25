# SIDEBAR-EDITOR

`sbedit` is a command line tool which can list and manipulate the favorite items shown in the sidebar of the Finder windows

## DISCLAIMER

I am not a professionally trained developer. Everything I know about programming has been self-taught. As such, the code provided here is definitely not up to the standards of nowadays programming. Any help cleaning the code would be very welcome.

## History

In the past, many MacAdmins had been using the tool [mysides](https://github.com/mosen/mysides) to manage the sidebar items. This tool has worked at least until macOS 13 Ventura, and some reports has seen it work on macOS 14 Sonoma. Most of the API used by mysides is deprecated.

Starting with macOS 13, the sidebar favorite items are stored in a .sfl3 file (.sfl4, starting with macOS 26) that mysides cannot handle.

A Python method exists: [FinderSidebarEditor](https://github.com/robperc/FinderSidebarEditor), but it uses the same deprected API through PyObjC. Why it still works is a mystery.

However, this Python script, while still working, is quite slow.

This is why I wanted to find a way to manipulate the Finder sidebar with a compiled executable that uses modern APIs.

That said, the way `sbedit` manipulates the favorite items is by no means an official, Apple supported method. It could break at any time.

## Requirements

MacOS 13+. Tested on macOS 13, macOS 15 and macOS 26.

`sbedit` might require to have access to all files to be able to read the necessary files. This can be done manually by dragging the binary to System Settings -> Confidentiality & Security -> Access to all files (full disk access). This can be done with a Configuration Profile.

## Usage

Here is the usage you get when calling `sbedit` without any arguments :

```
  sbedit command [arguments]

    LIST OF POSSIBLE COMMANDS :
         --add           add all the paths provided as arguments to the sidebar
         --removeAll     remove all items from the sidebar
         --remove        remove the item path provided as argument from the 
                         sidebar
         --list          display the list of paths currently in the sidebar
         --reload        reloads the Finder sidebar. This command takes an 
                         optional argument "--force". See discussion below.
         --version       prints the version number
         
    RELOADING THE FINDER SIDEBAR
    
    Reloading the Finder Sidebar is done by restarting the sharedfilelistd 
    daemon. However, the changes to the Finder sidebar can take up to a minute 
    to be visible. To speed up the reloading process, you can provide the 
    --force argument, which will kill and restart the Finder, thus making 
    the changes immediately visible.
```    

### Adding items to the sidebar

the `--add` command will take as many paths as you want and add them all to the favorite items of the sidebar, in the order you have provided them. Path can use the `~` to target the user's home folder.

Exemple : 

```
sbedit --add "~/Documents" "/Applications" "~/Download"
```

### Removing all items from the sidebar

The `--removeAll` command will remove all items from the favorite items of the sidebar.

### Removing a specific item from the sidebar

The `--remove` command will take a path as argument, and remove it from the sidebar. As with the `--add` command, you can use the `~` to target the user's home folder. This command is currently limited and you cannot specify multiple items, and you cannot provide only the name of an item to remove it. This is on the TODO list.

### Listing the items currently in the sidebar

The `--list` option will list the paths to the items currently in the sidebar. Please note that this list might not reflect what is visually shown in a currently open Finder window, as the service might have to be restarted (see the `--reload` option below)

### Reload the services to make the changes visible

The `--reload` command will restart the `sharedfilelistd` process to force it to load the new settings. If you run sbedit at login, for example with a tool like [Outset](https://github.com/macadmins/outset) when now Finder window is open, this command might suffice. However, if Finder windows are already displayed on the screen, the change might take more than a minute to be taken into account. If you want to force and speedup the process, you can add the `--force` argument to that command. This will kill and reload the Finder, thus applying the new settings immediately. However, this comes at the cost of a "flicker" as the Finder quits and reloads.
    
## Discussion and design choices

When a new user logs on a computer, as long as no Finder window is opened, the `com.apple.LSSharedFileList.FavoriteItems.sfl3` (or .sfl4) file does not exist. When the first Finder window is opened, macOS creates that file and populates it with default items.
I have decided that when trying to list, add, or remove items when the `com.apple.LSSharedFileList.FavoriteItems.sfl3` (or .sfl4) file does not exist, `sbedit` will create that file with an empty array of items.

## Credits

This code was heavily inspired by an [Applescript by com.cocolog-nifty.quicktimer](https://quicktimer.cocolog-nifty.com/icefloe/2024/03/post-7f4cb0.html).
