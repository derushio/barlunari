import BarlunariDomain

/// メニューバーの残り時間の対象から外した予定の保存先。
public protocol CountdownExclusionRepository: Sendable {
    func load() async -> CountdownExclusions

    /// 保存済みの集約を読み、`body` で変更して保存するまでを原子的に行う。
    ///
    /// 同時に呼ばれても、互いの変更を失わない。読んでから書くまでの間に他の更新が割り込まないよう、
    /// 実装は呼び出しを直列化する。保存に失敗したら投げ、そのときは変更を保存しない。
    func update(_ body: @Sendable (inout CountdownExclusions) -> Void) async throws
}
