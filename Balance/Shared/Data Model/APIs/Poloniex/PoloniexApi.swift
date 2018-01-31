//
//  PoloniexApi.swift
//  BalanceForBlockchain
//
//  Created by Raimon Lapuente on 13/06/2017.
//  Copyright © 2017 Balanced Software, Inc. All rights reserved.
//

import Foundation
import Security

/*
 All calls to the trading API are sent via HTTP POST to https://poloniex.com/tradingApi and must contain the following headers:
 
 Key - Your API key.
 Sign - The query's POST data signed by your key's "secret" according to the HMAC-SHA512 method.
 
 
 Additionally, all queries must include a "nonce" POST parameter. The nonce parameter is an integer which must always be greater than the previous nonce used.
 
 */

class PoloniexApi: ExchangeApi {
    
    fileprivate enum Commands: String {
        case returnBalances
        case returnCompleteBalances
        case returnDepositAddresses
        case generateNewAddress
        case returnDepositsWithdrawals
        case returnOpenOrders
        case returnTradeHistory
        case returnOrderTrades
        case buy
        case sell
        case cancelOrder
        case moveOrder
        case withdraw
        case returnFeeInfo
        case returnAvailableAccountBalances
        case returnTradableBalances
        case transferBalance
        case returnMarginAccountSummary
        case marginBuy
        case marginSell
        case getMarginPosition
        case closeMarginPosition
        case createLoanOffer
        case cancelLoanOffer
        case returnOpenLoanOffers
        case returnActiveLoans
        case returnLendingHistory
        case toggleAutoRenew
    }
    
    // MARK: - Constants -
    
    fileprivate let tradingURL = URL(string: "https://poloniex.com/tradingApi")!
    
    // MARK: - Properties -
    
    fileprivate var secret: String
    fileprivate var key: String
    
    // MARK: - Lifecycle -
    
    init() {
        self.secret = ""
        self.key = ""
    }

    init(secret: String, key: String) {
        self.secret = secret
        self.key = key
    }
    
    // MARK: - Public -
    
    func authenticationChallenge(loginStrings: [Field], existingInstitution: Institution? = nil, closeBlock: @escaping (Bool, Error?, Institution?) -> Void) {
        assert(loginStrings.count == 2, "number of auth fields should be 2 for Poloniex")
        var secretField : String?
        var keyField : String?
        for field in loginStrings {
            if field.type == .key {
                keyField = field.value
            } else if field.type == .secret {
                secretField = field.value
            } else {
                assert(false, "wrong fields are passed into the poloniex auth, we require secret and key fields and values")
            }
        }
        guard let secret = secretField, let key = keyField else {
            assert(false, "wrong fields are passed into the poloniex auth, we require secret and key fields and values")

            closeBlock(false, "wrong fields are passed into the poloniex auth, we require secret and key fields and values", nil)
            return
        }
        do {
            try authenticate(secret: secret, key: key, existingInstitution: existingInstitution, closeBlock: closeBlock)
        } catch {
        
        }
    }
    
    func fetchBalances(institution: Institution, completion: @escaping SuccessErrorBlock) {
        let requestInfo = createRequestBodyandHash(params: ["command": Commands.returnCompleteBalances.rawValue], secret: secret, key: key)
        let urlRequest = assembleTradingRequest(key: key, body: requestInfo.body, hashBody: requestInfo.signedBody)
        
        let datatask = certValidatedSession.dataTask(with: urlRequest) { data, response, error in
            do {
                if let safeData = data {
                    //create accounts
                    let poloniexAccounts = try self.parsePoloniexAccounts(data: safeData)
                    self.processPoloniexAccounts(accounts: poloniexAccounts, institution: institution)
                } else {
                    log.error("Poloniex Error: \(String(describing: error))")
                    log.error("Poloniex Data: \(String(describing: data))")
                }
                async {
                    completion(false, error)
                }
            }
            catch {
                log.error("Failed to Poloniex balance data: \(error)")
                async {
                    completion(false, error)
                }
            }
        }
        datatask.resume()
    }
    
    // MARK: - Private -
    
    fileprivate func findError(data: Data) -> String? {
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: AnyObject] else {
                throw PoloniexApi.CredentialsError.bodyNotValidJSON
            }
            if dict.keys.count == 1 {
                if let errorDict = dict["error"] {
                    return errorDict as? String
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // Poloniex doesn't have an authenticate method "per-se" so we use the returnBalances call to validate the key-secret pair for login
    fileprivate func authenticate(secret: String, key: String, existingInstitution: Institution?, closeBlock: @escaping (Bool, Error?, Institution?) -> Void) throws {
        self.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let requestInfo = createRequestBodyandHash(params: ["command": Commands.returnCompleteBalances.rawValue], secret: secret, key: key)
        let urlRequest = assembleTradingRequest(key: key, body: requestInfo.body, hashBody: requestInfo.signedBody)
        let datatask = certValidatedSession.dataTask(with: urlRequest) { data, response, error in
            do {
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 400, 403:
                        throw PoloniexApi.CredentialsError.incorrectLoginCredentials
                    default: break
                    }
                }
                
                if let safeData = data {
                    //if error exists should be reported to UI data
                    if let _ = self.findError(data: safeData) {
                        throw PoloniexApi.CredentialsError.incorrectLoginCredentials
                    }
                    
                    // Create (or update) the institution and finish (we do not have access tokens)
                    if let institution = existingInstitution ?? InstitutionRepository.si.institution(source: .poloniex, sourceInstitutionId: "", name: "Poloniex") {
                        institution.secret = secret
                        institution.apiKey = key
                        if let existingInstitution = existingInstitution {
                            existingInstitution.passwordInvalid = false
                            existingInstitution.replace()
                        }
                        
                        //create accounts
                        let poloniexAccounts = try self.parsePoloniexAccounts(data: safeData)
                        self.processPoloniexAccounts(accounts: poloniexAccounts, institution: institution)
                        async {
                            closeBlock(true, nil, institution)
                        }
                    } else {
                        throw "Error creating institution"
                    }
                } else {
                    log.error("Poloniex Error: \(String(describing: error))")
                    log.error("Poloniex Data: \(String(describing: data))")
                    throw PoloniexApi.CredentialsError.bodyNotValidJSON
                }
            } catch {
                log.error("Failed to Poloniex balance login data: \(error)")
                async {
                    closeBlock(false, error, nil)
                }
            }
        }
        datatask.resume()
    }
    
    fileprivate func createRequestBodyandHash(params: [String: String], secret: String, key: String) -> (body: String, signedBody: String) {
        let nonce = Int64(Date().timeIntervalSince1970 * 10000)

        var queryItems = [URLQueryItem]()
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        queryItems.append(URLQueryItem(name: "nonce", value: "\(nonce)"))
        
        var components = URLComponents()
        components.queryItems = queryItems
        
        let body = components.query!
        let signedPost = CryptoAlgorithm.sha512.hmac(body: body, key: secret)
        
        return (body, signedPost)
    }
    
    fileprivate func assembleTradingRequest(key: String, body: String, hashBody: String) -> URLRequest {
        var request = URLRequest(url: tradingURL)
        request.httpMethod = HTTPMethod.POST
        request.setValue(key, forHTTPHeaderField: "Key")
        request.setValue(hashBody, forHTTPHeaderField: "Sign")
        request.httpBody = body.data(using: .utf8)!
        return request
    }
    
}

//TODO: check if these code is needed
extension PoloniexAccount {
    var altCurrency: Currency {
        return Currency.rawValue("BTC")
    }
    
    var balance: Int {
        let balance = available * Decimal(pow(10.0, Double(currency.decimals)))
        return (balance as NSDecimalNumber).intValue
    }
    
    var altBalance: Int {
        let altBalance = btcValue * Decimal(pow(10.0, Double(altCurrency.decimals)))
        return (altBalance as NSDecimalNumber).intValue
    }
    
}

extension Institution {
    fileprivate var apiKeyKey: String { return "apiKey institutionId: \(institutionId)" }
    var apiKey: String? {
        get {
            return keychain[apiKeyKey, "apiKey"]
        }
        set {
            log.debug("set apiKeyKey: \(apiKeyKey)  newValue: \(String(describing: newValue))")
            keychain[apiKeyKey, "apiKey"] = newValue
        }
    }
    
    fileprivate var secretKey: String { return "secret institutionId: \(institutionId)" }
    var secret: String? {
        get {
            return keychain[apiKeyKey, "secret"]
        }
        set {
            log.debug("set secretKey: \(secretKey)  newValue: \(String(describing: newValue))")
            keychain[apiKeyKey, "secret"] = newValue
        }
    }
}

// MARK: Transactions

internal extension PoloniexApi {
    internal func fetchTransactions(institution: Institution, completion: @escaping SuccessErrorBlock) {
        let parameters: [String : String] = [
            "command" : Commands.returnDepositsWithdrawals.rawValue,
            "start" : "0",
            "end" : "\(Date().timeIntervalSince1970)"
        ]
        
        let requestInfo = createRequestBodyandHash(params: parameters, secret: secret, key: key)
        let urlRequest = assembleTradingRequest(key: key, body: requestInfo.body, hashBody: requestInfo.signedBody)
        
        let datatask = certValidatedSession.dataTask(with: urlRequest) { data, response, error in
            do {
                if let safeData = data {
                    //create accounts
                    let poloniexTransactions = try self.parsePoloniexTransactions(data: safeData)
                    poloniexTransactions.forEach {
                        $0.institutionId = institution.institutionId
                        $0.sourceInstitutionId = institution.sourceInstitutionId
                    }
                    self.processPoloniexTransactions(transactions: poloniexTransactions)
                    
                    async {
                        completion(true, error)
                    }
                } else {
                    log.error("Poloniex Error: \(String(describing: error))")
                    log.error("Poloniex Data: \(String(describing: data))")
                    
                    async {
                        completion(false, error)
                    }
                }
            }
            catch {
                log.error("Failed to Poloniex balance data: \(error)")
                async {
                    completion(false, error)
                }
            }
        }
        datatask.resume()
        
    }

}

//TODO: MOVE TO THE NEW API
private extension PoloniexApi {
    
    // MARK: Accounts
    func parsePoloniexAccounts(data: Data) throws -> [NewPoloniexAccount] {
//        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: AnyObject] else {
//            throw PoloniexApi.CredentialsError.bodyNotValidJSON
//        }
//
//        let flatDict = dict.map { (key, value) -> [String : AnyObject] in
//            if var dict = value as? [String: AnyObject] {
//                dict["currency"] = key as AnyObject
//                return dict
//            }
//            return [:]
//        }
//
//        if let serialized = try? JSONSerialization.data(withJSONObject: flatDict, options: .prettyPrinted),
//            let accounts = PoloniexAPI2.buildObject(from: serialized, for: .accounts) as? [NewPoloniexAccount] {
//
//            return accounts
//        }
//
        return []
    }
    
    func processPoloniexAccounts(accounts: [NewPoloniexAccount], institution: Institution) {
        for account in accounts {
            // Create or update the local account object
            updateLocal(account: account, institution: institution)
        }
        
        let accounts = AccountRepository.si.accounts(institutionId: institution.institutionId)
        for account in accounts {
            let index = accounts.index(where: {$0.currency == account.currency})
            if index == nil {
                // This account doesn't exist in the response, so remove it
                AccountRepository.si.delete(account: account)
            }
        }
    }

    // this is the function to save into a repository
    func updateLocal(account: NewPoloniexAccount, institution: Institution) {
        // Poloniex doesn't have id's per-se, the id a coin is the coin symbol itself
        if let newAccount = AccountRepository.si.account(institutionId: institution.institutionId,
                                                         source: institution.source,
                                                         sourceAccountId: account.currency.code,
                                                         sourceInstitutionId: "",
                                                         accountTypeId: account.accountType,
                                                         accountSubTypeId: nil,
                                                         name: account.currency.code,
                                                         currency: account.currency.code,
                                                         currentBalance: account.currentBalance,
                                                         availableBalance: nil,
                                                         number: nil,
                                                         altCurrency: account.altCurrency.code,
                                                         altCurrentBalance: account.altCurrentBalance,
                                                         altAvailableBalance: nil) {
            
            // Hide unpoplular currencies that have a 0 balance
            if account.currency != Currency.btc && account.currency != Currency.eth {
                let isHidden = (account.currentBalance == 0)
                if newAccount.isHidden != isHidden {
                    newAccount.isHidden = isHidden
                }
            }
            
        }
        
    }
    
    // MARK: Transactions
    func parsePoloniexTransactions(data: Data) throws -> [NewPoloniexTransaction] {
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String : AnyObject] else {
            throw PoloniexApi.CredentialsError.bodyNotValidJSON
        }
        
        var transactions = [NewPoloniexTransaction]()
        
//        if let depositsJSON = json["deposits"] as? [[String : Any]],
//            let serialized = try? JSONSerialization.data(withJSONObject: depositsJSON, options: .prettyPrinted),
//            let deposits = PoloniexAPI2.buildObject(from: serialized, for: .transactions) as? [NewPoloniexTransaction] {
//
//            deposits.forEach { $0.category = .deposit }
//            transactions += deposits
//
//        }
//
//        if let withdrawalsJSON = json["withdrawals"] as? [[String : Any]],
//            let serialized = try? JSONSerialization.data(withJSONObject: withdrawalsJSON, options: .prettyPrinted),
//            let withdrawals = PoloniexAPI2.buildObject(from: serialized, for: .transactions) as? [NewPoloniexTransaction] {
//
//            withdrawals.forEach { $0.category = .withdrawal }
//            transactions += withdrawals
//
//        }
        
        return transactions
    }
    
    func processPoloniexTransactions(transactions: [NewPoloniexTransaction]) {
        for transaction in transactions {
            TransactionRepository.si.transaction(source: transaction.source, sourceTransactionId: transaction.sourceTransactionId, sourceAccountId: transaction.sourceAccountId, name: transaction.name, currency: transaction.currencyCode, amount: transaction.amount, date: transaction.date, categoryID: nil, sourceInstitutionId: transaction.sourceInstitutionId, institutionId: transaction.institutionId)
        }
    }
}
