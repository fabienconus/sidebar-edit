// sbedit, a tool to edit the Finder's sidebar items
// by acting on the com.apple.LSSharedFileList.FavoriteItems.sfl3 file
//
// Works with macOS 14 and later (for the SFL3 file format)
// 
// Inspired by the AppleScript by com.cocolog-nifty.quicktimer
// https://quicktimer.cocolog-nifty.com/icefloe/2024/03/post-7f4cb0.html
// 
// Fabien Conus, 11.11.2025

import Foundation
import AppKit

let version = "1.0"

enum MyError: Error {
    case inputOutputError(String)
    case pathError(String)
    case structureError(String)
    case bookmarkError(String )
}

func main() {
    // Initialize the path to the SFL3 file
    guard let sharedFileListURL = try? getSFL3path() else
    {
        logerror("Unable to get URL for the SFL3 file")
        exit(1)
    }
    if !FileManager.default.fileExists(atPath: sharedFileListURL.path) {
        createEmptySFL3(to: sharedFileListURL)
    }
        
    // First argument is always the path to the binary, drop it.
    let arguments = CommandLine.arguments.dropFirst()
    
    // Retrieve the comman
    let command = arguments.first
    
    switch command {
    case "--add":
        let itemPaths = Array(arguments.dropFirst())
        add(items: itemPaths, to:sharedFileListURL)
    case "--removeAll":
        print("Removing all items from the sidebar")
        removeAll(from: sharedFileListURL)
    case "--reload":
        let force = arguments.contains(where: { $0 == "--force" })
        reloadServices(force: force)
    case "--list":
        list(contentof: sharedFileListURL)
    case "--remove":
        let itemPath = arguments.dropFirst().first ?? "no item"
        do {
            try remove(item: itemPath, from: sharedFileListURL)
        } catch {
            logerror(error.localizedDescription)
            exit(1)
        }
    case "--version":
        print(version)
        exit(0)
    default:
        usage()
        exit(1)
    }
}

func usage() {
    let usage = """
sbedit: a tool to manipulate the Finder sidebar
  usage: sbedit command [arguments]

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
"""
    print(usage)
}

// allows easy printing to stdErr
// from https://gist.github.com/algal/0a9aa5a4115d86d5cc1de7ea6d06bd91
extension FileHandle : TextOutputStream {
  public func write(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    self.write(data)
  }
}

func logerror(_ error : String) {
  var standardError = FileHandle.standardError
  print(error, to:&standardError)
}

func add(items itemPaths:[String], to sharedFileList:URL) {
    if itemPaths.isEmpty {
        usage()
        exit(1)
    }
    
    // Open the com.apple.LSSharedFileList.FavoriteItems.sfl3 file
    guard let archiveDictM = try? openSFL3(sharedFileListURL: sharedFileList)
    else {
        logerror("Error reading SFL3 file")
        exit(1)
    }
    
    // Traiter chaque chemin fourni et suivre les succès
    var hasSuccess = false
    
    for itemPath in itemPaths {
        do {
           try addItem(itemPath: itemPath, to:archiveDictM)
            hasSuccess = true
        } catch {
            logerror("Error adding item \(itemPath): \(error)")
        }
    }
        
    if !hasSuccess {
        exit(1)
    }
    
    // Save the com.apple.LSSharedFileList.FavoriteItems.sfl3 file
    do {
        try saveSFL3(file: sharedFileList, archiveDictM: archiveDictM)
    } catch {
        logerror(error.localizedDescription)
        exit(1)
    }
}

func removeAll(from sharedFileListURL:URL) {
    guard let archiveDictM = try? openSFL3(sharedFileListURL: sharedFileListURL)
    else {
        logerror("Error reading SLF3 file")
        exit(1)
    }
    
    let itemsArrayM = NSMutableArray()
    
    // Updating the main dictionary
    archiveDictM.setObject(itemsArrayM, forKey: "items" as NSString)
    
    // Save the com.apple.LSSharedFileList.FavoriteItems.sfl3 file
    do {
        try saveSFL3(file: sharedFileListURL, archiveDictM: archiveDictM)
    } catch {
        logerror(error.localizedDescription)
    }
}

func remove(item itemPath:String, from sharedFileListURL:URL) throws {
    guard let archiveDictM = try? openSFL3(sharedFileListURL: sharedFileListURL)
    else {
        logerror("Error reading SLF3 file")
        exit(1)
    }
    
    // ============================================
    // Standardizing path
    // ============================================
    let pathString = (itemPath as NSString).standardizingPath
    guard let addDirURL = URL(fileURLWithPath: pathString).absoluteURL as URL? else {
        logerror("Error : invalid path - \(itemPath)")
        throw MyError.pathError("Erreur : chemin invalide - \(itemPath)")
    }
    
    let absoluteString = addDirURL.absoluteString
    
    // ============================================
    // Processing items
    // ============================================
    guard let itemsArray = archiveDictM.object(forKey: "items") as? NSArray else {
        logerror("Error: unable to read the items array")
        exit(1)
    }
    
    let itemsArrayM = NSMutableArray(array: itemsArray)
    
    for item in itemsArrayM {
        guard let itemDict = item as? NSDictionary,
              let bookmarkData = itemDict.object(forKey: "Bookmark") as? Data else {
            continue
        }
        
        var isStale = false
        if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            if bookmarkURL.absoluteString == absoluteString {
                // Item was found -> remove it
                itemsArrayM.remove(item)
                break
            }
        }
    }
    
    // Updating the main dictionary
    archiveDictM.setObject(itemsArrayM, forKey: "items" as NSString)
    
    // Save the com.apple.LSSharedFileList.FavoriteItems.sfl3 file
    do {
        try saveSFL3(file: sharedFileListURL, archiveDictM: archiveDictM)
    } catch {
        logerror(error.localizedDescription)
    }
}

func list(contentof sharedFileListURL:URL) {
    guard let archiveDictM = try? openSFL3(sharedFileListURL: sharedFileListURL)
    else {
        logerror("Error reading SLF3 file")
        exit(1)
    }
        
    // ============================================
    // Processing items
    // ============================================
    guard let itemsArray = archiveDictM.object(forKey: "items") as? NSArray else {
        logerror("Error: unable to read the items array")
        exit(1)
    }
    
    for item in itemsArray {
        guard let itemDict = item as? NSDictionary,
              let bookmarkData = itemDict.object(forKey: "Bookmark") as? Data else {
            continue
        }
        
        var isStale = false
        if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            // Printing the path to the item to the standard output
            print(bookmarkURL.absoluteString)
        }
    }
}

func addItem(itemPath: String, to archiveDictM:NSMutableDictionary) throws {
    // ============================================
    // Standardizing path
    // ============================================
    let pathString = (itemPath as NSString).standardizingPath
    guard let addDirURL = URL(fileURLWithPath: pathString).absoluteURL as URL? else {
        logerror("Error: invalid path - \(itemPath)")
        throw MyError.pathError("Error: invalid path - \(itemPath)")
    }
    
    let absoluteString = addDirURL.absoluteString
    print("Adding path: \(absoluteString)")
    
    
    // ============================================
    // Processing items
    // ============================================
    guard let itemsArray = archiveDictM.object(forKey: "items") as? NSArray else {
        logerror("Error: unable to read the items array")
        throw MyError.structureError("Error: unable to read the items array")
    }
    
    let itemsArrayM = NSMutableArray(array: itemsArray)
    
    // Checking if the item already exists
    for item in itemsArrayM {
        guard let itemDict = item as? NSDictionary,
              let bookmarkData = itemDict.object(forKey: "Bookmark") as? Data else {
            continue
        }
        
        var isStale = false
        if let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            if bookmarkURL.absoluteString == absoluteString {
                logerror("Item \(absoluteString) already exists in the sidebar")
                throw MyError.pathError("Item \(absoluteString) already exists in the sidebar")
            }
        }
    }
    
    // ============================================
    // Adding the new item
    // ============================================
    let newItemDict = NSMutableDictionary()
    
    // CustomItemProperties (the user's Desktop must not take any properties, otherwise it won't show)
    if !addDirURL.lastPathComponent.contains("Desktop") {
        let customProperties = NSMutableDictionary()
        customProperties.setValue(NSNumber(value: 1), forKey: "com.apple.LSSharedFileList.ItemIsHidden") // 0=true, 1=false
        customProperties.setValue(NSNumber(value: 0), forKey: "com.apple.finder.dontshowonreappearance") // 0=true, 1=false
        
        
        newItemDict.setObject(customProperties, forKey: "CustomItemProperties" as NSString)
    }
    // UUID
    let uuid = UUID().uuidString
    newItemDict.setValue(uuid, forKey: "uuid")
    
    // Visibility
    newItemDict.setValue(NSNumber(value: 0), forKey: "visibility")
    
    // Bookmark
    if let bookmarkData = try? addDirURL.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) {
        newItemDict.setObject(bookmarkData, forKey: "Bookmark" as NSString)
    } else {
        print("Error: unable to create a bookmark for \(absoluteString)")
        throw MyError.bookmarkError("Error: unable to create a bookmark for \(absoluteString)")
    }
    
    // Addind the item to the array
    itemsArrayM.add(newItemDict)
    print("Item \(addDirURL.lastPathComponent) successfuly added")
    
    // Updating the main dictionary
    archiveDictM.setObject(itemsArrayM, forKey: "items" as NSString)
}

func reloadServices(force:Bool) {
    print("Rechargement des services...")
    
    var forceReload = force
    
    // Try to kill the sharedfilelistd process
    let killProcess = Process()
    killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    killProcess.arguments = ["sharedfilelistd"]
    
    do {
        try killProcess.run()
        killProcess.waitUntilExit()
    } catch {
        //print("Unable to kill process")
        // Killing the sharedfilelistd process failed, revert to killing the Finder
        forceReload = true
    }
    
    if forceReload {
        // Reload the Finder
        let killFinder = Process()
        killFinder.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killFinder.arguments = ["Finder"]
        try? killFinder.run()
    }
    
    print("Services reloaded")
}

func getSFL3path() throws -> URL {
    // ============================================
    // Getting the path to the SFL3 file
    // ============================================
    let fileManager = FileManager.default
    let fileName = "com.apple.LSSharedFileList.FavoriteItems.sfl3"
    
    guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        print("Error: unable to find the Application Support folder")
        throw MyError.inputOutputError("Error: unable to find the Application Support folder")
    }
    
    let containerURL = appSupportURL.appendingPathComponent("com.apple.sharedfilelist", isDirectory: true)
    let sharedFileListURL = containerURL.appendingPathComponent(fileName, isDirectory: false)
    
    return sharedFileListURL
}

func openSFL3(sharedFileListURL:URL) throws -> NSMutableDictionary {
    // ============================================
    // Reading and unarchiving the SFL3 file
    // ============================================
    guard let plistData = try? Data(contentsOf: sharedFileListURL) else {
        print("Error: unable to read the SFL3 file. Make sure you have provided the necessary access rights to sbedit.")
        throw MyError.inputOutputError("Error: unable to read the SFL3 file.")
    }
    
    // Authorized classes for Unarchiving
    let allowedClasses: [AnyClass] = [
        NSDictionary.self,
        NSMutableDictionary.self,
        NSArray.self,
        NSMutableArray.self,
        NSString.self,
        NSMutableString.self,
        NSData.self,
        NSMutableData.self,
        NSNumber.self,
        NSUUID.self,
        NSDate.self
    ]
    
    var archivedDict:NSDictionary
    do {
        archivedDict = try NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: plistData) as! NSDictionary
    } catch {
        logerror("Error: unable to unarchive data: \(error)")
        throw error
    }
    
    let archiveDictM = NSMutableDictionary(dictionary: archivedDict)
    
    return archiveDictM
}

func saveSFL3(file sharedFileListURL:URL, archiveDictM:NSMutableDictionary) throws {
    // ============================================
    // Archiving and writing to disk
    // ============================================
    guard let saveData = try? NSKeyedArchiver.archivedData(withRootObject: archiveDictM, requiringSecureCoding: false) else {
        print("Error: unable to archive data")
        throw MyError.inputOutputError("Error: unable to archive data")
    }
    
    do {
        try saveData.write(to: sharedFileListURL, options: [])
        print("Modifications sucessfuly saved.")
    } catch {
        logerror("Error while saveing the SFL3 file: \(error)")
        throw error
    }
    
}

func createEmptySFL3(to file:URL) {
    print("Creating an empty SFL3 file")
    let archiveDictM = NSMutableDictionary()
    
    let items = NSArray()
    archiveDictM.setObject(items, forKey: NSString("items"))
    
    let properties = NSDictionary(object: true, forKey: NSString("com.apple.LSSharedFileList.ForceTemplateIcons"))
    archiveDictM.setObject(properties, forKey: NSString("properties"))
    
    do {
        try saveSFL3(file: file, archiveDictM: archiveDictM)
    } catch {
        print(error)
    }
}

// Exécution du script
main()
