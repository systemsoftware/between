import Foundation

func ping(_ url: URL) async -> Bool {    
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 5.0
    
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return true
        }
    } catch {
        print("Request failed with error: \(error.localizedDescription)")
    }
    
    return false
}
