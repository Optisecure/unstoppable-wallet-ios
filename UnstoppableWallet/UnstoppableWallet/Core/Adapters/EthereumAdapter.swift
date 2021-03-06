import EthereumKit
import RxSwift

class EthereumAdapter: EthereumBaseAdapter {
    static let decimal = 18

    init(ethereumKit: EthereumKit.Kit) {
        super.init(ethereumKit: ethereumKit, decimal: EthereumAdapter.decimal)
    }

    private func transactionRecord(fromTransaction transaction: TransactionInfo) -> TransactionRecord {
        var type: TransactionType = .sentToSelf
        var amount: Decimal = 0

        if let significand = Decimal(string: transaction.value) {
            amount = Decimal(sign: .plus, exponent: -decimal, significand: significand)

            let mineAddress = ethereumKit.receiveAddress.lowercased()
            let fromMine = transaction.from.lowercased() == mineAddress
            let toMine = transaction.to.lowercased() == mineAddress

            if fromMine && !toMine {
                type = .outgoing
            } else if !fromMine && toMine {
                type = .incoming
            }
        }

        let failed = (transaction.isError ?? 0) != 0

        return TransactionRecord(
                uid: transaction.hash,
                transactionHash: transaction.hash,
                transactionIndex: transaction.transactionIndex ?? 0,
                interTransactionIndex: 0,
                type: type,
                blockHeight: transaction.blockNumber,
                amount: abs(amount),
                fee: transaction.gasUsed.map { Decimal(sign: .plus, exponent: -decimal, significand: Decimal($0 * transaction.gasPrice)) },
                date: Date(timeIntervalSince1970: transaction.timestamp),
                failed: failed,
                from: transaction.from,
                to: transaction.to,
                lockInfo: nil,
                conflictingHash: nil,
                showRawTransaction: false
        )
    }

    override func sendSingle(to address: String, value: String, gasPrice: Int, gasLimit: Int) -> Single<Void> {
        ethereumKit.sendSingle(to: address, value: value, gasPrice: gasPrice, gasLimit: gasLimit)
                .map { _ in ()}
                .catchError { [weak self] error in
                    Single.error(self?.createSendError(from: error) ?? error)
                }
    }

}

extension EthereumAdapter {

    static func clear(except excludedWalletIds: [String]) throws {
        try EthereumKit.Kit.clear(exceptFor: excludedWalletIds)
    }

}

// IAdapter
extension EthereumAdapter: IAdapter {

    func start() {
        // started via EthereumKitManager
    }

    func stop() {
        // stopped via EthereumKitManager
    }

    func refresh() {
        // refreshed via EthereumKitManager
    }

    var debugInfo: String {
        ethereumKit.debugInfo
    }

}

extension EthereumAdapter: IBalanceAdapter {

    var state: AdapterState {
        switch ethereumKit.syncState {
        case .synced: return .synced
        case .notSynced(let error): return .notSynced(error: error.convertedError)
        case .syncing: return .syncing(progress: 50, lastBlockDate: nil)
        }
    }

    var stateUpdatedObservable: Observable<Void> {
        ethereumKit.syncStateObservable.map { _ in () }
    }

    var balance: Decimal {
        balanceDecimal(balanceString: ethereumKit.balance, decimal: EthereumAdapter.decimal)
    }

    var balanceUpdatedObservable: Observable<Void> {
        ethereumKit.balanceObservable.map { _ in () }
    }

}

extension EthereumAdapter: ISendEthereumAdapter {

    func availableBalance(gasPrice: Int, gasLimit: Int) -> Decimal {
        max(0, balance - fee(gasPrice: gasPrice, gasLimit: gasLimit))
    }

    var ethereumBalance: Decimal {
        balance
    }

    var minimumRequiredBalance: Decimal {
        0
    }

    var minimumSpendableAmount: Decimal? {
        nil
    }

    func fee(gasPrice: Int, gasLimit: Int) -> Decimal {
        let value = Decimal(gasPrice) * Decimal(gasLimit)
        return value / pow(10, EthereumAdapter.decimal)
    }

    func estimateGasLimit(to address: String?, value: Decimal, gasPrice: Int?) -> Single<Int> {
        ethereumKit.estimateGas(to: address, amount: value.roundedString(decimal: decimal), gasPrice: gasPrice)
    }

}

extension EthereumAdapter: ITransactionsAdapter {

    var transactionRecordsObservable: Observable<[TransactionRecord]> {
        ethereumKit.transactionsObservable.map { [weak self] in
            $0.compactMap { self?.transactionRecord(fromTransaction: $0) }
        }
    }

    func transactionsSingle(from: TransactionRecord?, limit: Int) -> Single<[TransactionRecord]> {
        ethereumKit.transactionsSingle(fromHash: from?.transactionHash, limit: limit)
                .map { [weak self] transactions -> [TransactionRecord] in
                    transactions.compactMap { self?.transactionRecord(fromTransaction: $0) }
                }
    }

    func rawTransaction(hash: String) -> String? {
        nil
    }

}
