import BarlunariDomain

enum TestAccount {
    static let a = try! UserAccount(id: AccountID("source-a"), name: "Google")
    static let b = try! UserAccount(id: AccountID("source-b"), name: "仕事")
}
