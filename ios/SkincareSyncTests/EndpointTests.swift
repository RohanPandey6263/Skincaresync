import Foundation
import Testing
@testable import SkincareSync

struct EndpointTests {
    @Test func productSearchBuildsExpectedQuery() throws {
        let url = try API.searchProducts(brand: "CeraVe", name: "hydrating cleanser").url(relativeTo: TestSupport.base)
        #expect(url.absoluteString == "http://127.0.0.1:8000/api/products/search?brand=CeraVe&name=hydrating%20cleanser")
    }

    @Test func queryEncodingEscapesPlusAmpersandAndEquals() throws {
        let url = try API.productByCode("a+b&c=d").url(relativeTo: TestSupport.base)
        #expect(url.query(percentEncoded: true) == "value=a%2Bb%26c%3Dd")
        #expect(url.query(percentEncoded: false) == "value=a+b&c=d")
    }

    @Test func ingredientQueryRepeatsFunctionsAndOmitsDefaults() throws {
        var query = IngredientQuery()
        query.text = "retinol"
        query.functions = ["antioxidant", "skin-conditioning"]
        query.letter = "R"
        query.onlyWithInteractions = true
        query.limit = 25
        query.offset = 50
        let url = try API.ingredients(query).url(relativeTo: TestSupport.base)
        #expect(url.absoluteString == "http://127.0.0.1:8000/api/ingredients?q=retinol&limit=25&offset=50&functions=antioxidant&functions=skin-conditioning&letter=R&only_with_interactions=true")
    }

    @Test func basePathPrefixIsPreserved() throws {
        let base = URL(string: "https://example.test/skincare/")!
        let url = try API.health.url(relativeTo: base)
        #expect(url.absoluteString == "https://example.test/skincare/api/health")
    }

    @Test func csrfHeaderOnlyOnStateChangingRequests() throws {
        let get = try API.sessions.urlRequest(base: TestSupport.base, csrfToken: "token")
        #expect(get.value(forHTTPHeaderField: "X-CSRF-Token") == nil)
        let post = try API.logout.urlRequest(base: TestSupport.base, csrfToken: "token")
        #expect(post.value(forHTTPHeaderField: "X-CSRF-Token") == "token")
        #expect(post.httpMethod == "POST")
        let delete = try API.revokeSession(id: 7).urlRequest(base: TestSupport.base, csrfToken: "token")
        #expect(delete.httpMethod == "DELETE")
        #expect(delete.url?.path == "/api/auth/sessions/7")
    }

    @Test func timeoutsFollowTheContract() {
        #expect(API.health.timeout == 12)
        #expect(API.productByCode("1").timeout == 20)
        #expect(API.searchProducts(brand: "", name: "x").timeout == 20)
        #expect(API.ingredients(IngredientQuery()).timeout == 12)
    }

    @Test func analyzeBodyUsesSnakeCase() throws {
        let request = AnalyzeRequest(
            skinProfile: .init(skinType: "oily", concerns: ["acne", "anti-aging"]),
            amProducts: [.init(brand: "Brand", name: "Product", rawIngredientList: "Water, Niacinamide")],
            pmProducts: []
        )
        let endpoint = try API.analyze(request)
        let body = try #require(endpoint.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let profile = try #require(json["skin_profile"] as? [String: Any])
        #expect(profile["skin_type"] as? String == "oily")
        #expect(profile["concerns"] as? [String] == ["acne", "anti-aging"])
        let am = try #require(json["am_products"] as? [[String: Any]])
        #expect(am.first?["raw_ingredient_list"] as? String == "Water, Niacinamide")
        #expect((json["pm_products"] as? [Any])?.isEmpty == true)
        let urlRequest = try endpoint.urlRequest(base: TestSupport.base, csrfToken: nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func changePasswordBodyMatchesSchema() throws {
        let body = try #require(try API.changePassword(current: "old", new: "new").body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["current_password": "old", "password": "new"])
        let delete = try #require(try API.deleteAccount(currentPassword: "pw").body)
        let deleteJSON = try #require(try JSONSerialization.jsonObject(with: delete) as? [String: String])
        #expect(deleteJSON == ["current_password": "pw", "confirm": "DELETE"])
    }
}

struct ServerErrorTests {
    @Test func plainDetailBecomesServerError() {
        let body = Data(#"{"detail":"No ingredient list found for this product code"}"#.utf8)
        let error = LiveAPIClient.serverError(status: 404, body: body, retryAfter: nil)
        #expect(error == .server(status: 404, message: "No ingredient list found for this product code", retryAfterSeconds: nil))
        #expect(error.isNotFound)
    }

    @Test func rateLimitCarriesRetryAfter() {
        let body = Data(#"{"detail":"Too many requests. Please slow down and try again shortly."}"#.utf8)
        let error = LiveAPIClient.serverError(status: 429, body: body, retryAfter: "7")
        #expect(error.isRateLimited)
        #expect(error.message.contains("7 seconds"))
    }

    @Test func fieldErrorsBecomeValidation() {
        let body = Data(#"{"detail":[{"loc":["body","password"],"msg":"Value error, Choose a less common password.","type":"value_error"},{"loc":["body","email"],"msg":"value is not a valid email address","type":"value_error"}]}"#.utf8)
        let error = LiveAPIClient.serverError(status: 422, body: body, retryAfter: nil)
        #expect(error == .validation(fieldErrors: ["password": "Choose a less common password.", "email": "value is not a valid email address"]))
        #expect(error.status == 422)
    }

    @Test func statusFallbacksCoverContractCodes() {
        for status in [404, 408, 422, 429, 502, 503] {
            let error = LiveAPIClient.serverError(status: status, body: Data(), retryAfter: nil)
            #expect(error.message == APIError.fallbackMessage(for: status))
            #expect(!error.message.contains("("))
        }
    }

    @Test func nullBodyDetection() {
        #expect(LiveAPIClient.isJSONNull(Data("null".utf8)))
        #expect(LiveAPIClient.isJSONNull(Data(" null\n".utf8)))
        #expect(!LiveAPIClient.isJSONNull(Data("{}".utf8)))
    }

    @Test func urlErrorsMapToConnectivityCases() {
        #expect(APIError.from(urlError: URLError(.cancelled), host: "h") == .cancelled)
        #expect(APIError.from(urlError: URLError(.timedOut), host: "h") == .timeout)
        #expect(APIError.from(urlError: URLError(.notConnectedToInternet), host: "h") == .offline)
        #expect(APIError.from(urlError: URLError(.cannotConnectToHost), host: "h:8000") == .unreachable(host: "h:8000"))
    }
}

struct APIConfigurationTests {
    @Test func debugAcceptsHTTPLoopback() throws {
        let config = try APIConfiguration.parse("http://127.0.0.1:8000", requireHTTPS: false).get()
        #expect(config.baseURL.absoluteString == "http://127.0.0.1:8000")
        #expect(config.hostDescription == "127.0.0.1:8000")
    }

    @Test func releaseRejectsHTTPAndEmpty() {
        #expect(APIConfiguration.parse("http://127.0.0.1:8000", requireHTTPS: true) == .failure(.insecure("http://127.0.0.1:8000")))
        #expect(APIConfiguration.parse("", requireHTTPS: true) == .failure(.missing))
        #expect(APIConfiguration.parse("not a url", requireHTTPS: true) == .failure(.invalid("not a url")))
        #expect(APIConfiguration.parse("https://api.example.test", requireHTTPS: true).map(\.baseURL.host) == .success("api.example.test"))
    }
}
