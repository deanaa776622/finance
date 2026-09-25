import Foundation

struct Quote {
    var price: Decimal
    var currency: AssetCurrency?
    var usdTwdRate: Decimal?
}

enum QuoteClient {
    private static let endpoint = URL(string: "https://script.google.com/macros/s/AKfycbydO1G5uaoLlFgCC6lEBFEOeT0vwS5cycdMZ40Q20mxk9p-fNNws13cvBg3iqanpgqheQ/exec")!

    private struct Payload: Decodable {
        var status: String
        var price: Double?
        var currency: String?
        var usdtwd: Double?
    }

    static func fetch(symbol: String) async throws -> Quote {
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        guard let url = comps.url else { throw QuoteError.unavailable }
        let (data, _) = try await URLSession.shared.data(from: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.status == "success", let price = payload.price else {
            throw QuoteError.unavailable
        }
        return Quote(
            price: decimalPrice(price),
            currency: payload.currency.flatMap { AssetCurrency(rawValue: $0.uppercased()) },
            usdTwdRate: payload.usdtwd.map { Decimal($0) }
        )
    }

    /// Mid-market USD→TWD. The quote endpoint does not send a rate.
    static func fetchUsdTwd() async throws -> Decimal {
        struct Payload: Decodable {
            var result: String
            var rates: [String: Double]
        }
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.result == "success", let twd = payload.rates["TWD"] else {
            throw QuoteError.unavailable
        }
        return Decimal(twd)
    }

    /// Quote payloads are doubles; keep the stored NAV at two decimal places.
    private static func decimalPrice(_ value: Double) -> Decimal {
        let posix = Locale(identifier: "en_US_POSIX")
        let text = String(format: "%.2f", locale: posix, value)
        return Decimal(string: text, locale: posix) ?? Decimal(value)
    }

    static func fetchAll(symbols: [UUID: String]) async -> [UUID: Quote] {
        await withTaskGroup(of: (UUID, Quote?).self) { group in
            for (id, symbol) in symbols {
                group.addTask {
                    (id, try? await fetch(symbol: symbol))
                }
            }
            var out: [UUID: Quote] = [:]
            for await (id, quote) in group {
                if let quote { out[id] = quote }
            }
            return out
        }
    }
}

enum QuoteError: Error {
    case unavailable
}

extension AssetItem {
    mutating func apply(_ quote: Quote) {
        price = quote.price
        if let currency = quote.currency { self.currency = currency }
        if let rate = quote.usdTwdRate { usdTwdRate = rate }
    }
}
