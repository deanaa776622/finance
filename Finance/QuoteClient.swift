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
            price: Decimal(price),
            currency: payload.currency.flatMap { AssetCurrency(rawValue: $0.uppercased()) },
            usdTwdRate: payload.usdtwd.map { Decimal($0) }
        )
    }

    /// Mid-market USD→TWD. The quote endpoint does not send a rate.
    static func fetchUsdTwd() async throws -> Decimal {
        try await fetchTwdRate(for: .usd)
    }

    /// How many TWD one unit of `currency` buys. TWD itself is 1.
    /// ponytail: quote currency stays TWD until the user can choose one.
    static func fetchTwdRate(for currency: AssetCurrency) async throws -> Decimal {
        guard let rate = try await fetchTwdRates()[currency] else { throw QuoteError.unavailable }
        return rate
    }

    /// TWD value of one unit of every supported currency. One USD-based quote covers the menu.
    static func fetchTwdRates() async throws -> [AssetCurrency: Decimal] {
        struct Payload: Decodable {
            var result: String
            var rates: [String: Double]
        }
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.result == "success", let usdTwd = payload.rates["TWD"], usdTwd > 0 else {
            throw QuoteError.unavailable
        }
        var out: [AssetCurrency: Decimal] = [.twd: 1, .usd: Decimal(usdTwd)]
        for currency in AssetCurrency.allCases where currency != .twd && currency != .usd {
            guard let perUsd = payload.rates[currency.rawValue], perUsd > 0 else { continue }
            out[currency] = Decimal(usdTwd / perUsd)
        }
        return out
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

/// Latest TWD rate for each currency, kept across launches.
enum RateBook {
    private static let key = "twdRates.v1"

    static func rate(for currency: AssetCurrency) -> Decimal? {
        load()[currency]
    }

    static func merge(_ rates: [AssetCurrency: Decimal]) {
        var book = load()
        for (code, rate) in rates { book[code] = rate }
        let raw = Dictionary(uniqueKeysWithValues: book.map {
            ($0.key.rawValue, NSDecimalNumber(decimal: $0.value).stringValue)
        })
        UserDefaults.standard.set(raw, forKey: key)
    }

    private static func load() -> [AssetCurrency: Decimal] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else { return [:] }
        var out: [AssetCurrency: Decimal] = [:]
        for (key, value) in raw {
            if let code = AssetCurrency(rawValue: key), let rate = Decimal(string: value) {
                out[code] = rate
            }
        }
        return out
    }
}

extension AssetItem {
    mutating func apply(_ quote: Quote) {
        price = quote.price
        if let currency = quote.currency { self.currency = currency }
        if self.currency == .usd, let rate = quote.usdTwdRate { usdTwdRate = rate }
    }
}
