import Combine
import Foundation

@MainActor
final class WorldSessions: ObservableObject {
    private var activeID = World.demo.id
    private var sessions: [UUID: MUDSession] = [:]
    private var activeObservation: AnyCancellable?

    func session(for id: UUID) -> MUDSession {
        if let session = sessions[id] { return session }
        let session = MUDSession()
        sessions[id] = session
        if activeID == id { observe(session) }
        return session
    }

    func activate(_ id: UUID) {
        guard activeID != id else { _ = session(for: id); return }
        activeObservation?.cancel()
        activeID = id
        let session = session(for: id)
        observe(session)
        objectWillChange.send()
    }

    func reset(_ id: UUID) {
        sessions[id]?.reset()
    }

    func remove(_ id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.disconnect(announce: false)
        if activeID == id {
            activeObservation?.cancel()
            activeObservation = nil
        }
    }

    func disconnectAll() {
        sessions.values.forEach { $0.disconnect(announce: false) }
    }

    private func observe(_ session: MUDSession) {
        activeObservation = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
