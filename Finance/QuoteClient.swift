import Foundation

struct Quote {
    var price: Decimal
    var currency: AssetCurrency?
    var usdTwdRate: Decimal?
}

enum QuoteClient {
    /// ponytail: Yahoo chart, no key. The old script took ~4s per symbol. Swap the host if this starts refusing.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0"]
        return URLSession(configuration: config)
    }()

    private struct ChartPayload: Decodable {
        struct Chart: Decodable {
            struct Result: Decodable {
                struct Meta: Decodable {
                    var currency: String?
                    var regularMarketPrice: Double?
                }
                var meta: Meta
            }
            var result: [Result]?
        }
        var chart: Chart
    }

    static func fetch(symbol: String) async throws -> Quote {
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbol.isEmpty else { throw QuoteError.unavailable }
        for ticker in tickers(for: symbol) {
            if let quote = try? await chart(ticker) { return quote }
        }
        throw QuoteError.unavailable
    }

    /// Digit-leading codes are Taiwan listings. Try the main board, then OTC.
    private static func tickers(for symbol: String) -> [String] {
        if symbol.contains(".") || symbol.contains("=") { return [symbol] }
        guard symbol.first?.isNumber == true else { return [symbol] }
        return ["\(symbol).TW", "\(symbol).TWO"]
    }

    private static func chart(_ ticker: String) async throws -> Quote {
        let encoded = ticker.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ticker
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=1d") else {
            throw QuoteError.unavailable
        }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw QuoteError.unavailable }
        let payload = try JSONDecoder().decode(ChartPayload.self, from: data)
        guard let meta = payload.chart.result?.first?.meta, let price = meta.regularMarketPrice else {
            throw QuoteError.unavailable
        }
        return Quote(
            price: Decimal(price),
            currency: meta.currency.flatMap { AssetCurrency(rawValue: $0.uppercased()) }
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
        let pairs = symbols.compactMap { id, symbol -> (UUID, String)? in
            let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (id, trimmed)
        }
        let bySymbol: [String: Quote] = await withTaskGroup(of: (String, Quote?).self) { group in
            for symbol in Set(pairs.map(\.1)) {
                group.addTask { (symbol, try? await fetch(symbol: symbol)) }
            }
            var out: [String: Quote] = [:]
            for await (symbol, quote) in group {
                if let quote { out[symbol] = quote }
            }
            return out
        }
        return Dictionary(uniqueKeysWithValues: pairs.compactMap { id, symbol in
            bySymbol[symbol].map { (id, $0) }
        })
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

    static func rates() -> [AssetCurrency: Decimal] {
        load()
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
