// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// App-owned text uses an explicit language preference. Original license
/// documents and file names are displayed verbatim in either language.
enum AppText {
    static var language: String {
        let preference=UserDefaults.standard.string(forKey:"appLanguage") ?? "system"
        if preference=="ja" || preference=="en" { return preference }
        return Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en"
    }
    static let english: [String:String] = {
        guard let url=Bundle.main.url(forResource:"English",withExtension:"json",subdirectory:"Localization"),
              let data=try? Data(contentsOf:url),
              let table=try? JSONDecoder().decode([String:String].self,from:data) else { return [:] }
        return table
    }()
    static func format(_ key: String, language: String, table: [String:String], arguments: [String]) -> String {
        let template=language=="en" ? (table[key] ?? key) : key
        return String(format:template,locale:Locale(identifier:language),arguments:arguments.map { $0 as NSString })
    }
}
func L(_ key: String,_ arguments: Any...) -> String {
    AppText.format(key,language:AppText.language,table:AppText.english,arguments:arguments.map { String(describing:$0) })
}
