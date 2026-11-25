// SPDX-License-Identifier: GPL-3.0-only
import Combine
import Foundation

/// A screen owns its pagination/read task. Leaving it cancels work before rows or cursors commit.
@MainActor
final class AccountScreenLease:ObservableObject {
    private var revision=UUID()
    private var work:Task<Void,Never>?

    @discardableResult
    func start(_ operation:@escaping @MainActor () async -> Void) -> Task<Void,Never> {
        let previous=work
        previous?.cancel()
        let expected=UUID();revision=expected
        let task=Task { @MainActor [weak self] in
            await previous?.value
            guard let self,self.revision==expected,!Task.isCancelled else{return}
            await operation()
            if self.revision==expected {self.work=nil}
        }
        work=task
        return task
    }
    func perform(_ operation:@escaping @MainActor () async -> Void) async {
        guard !Task.isCancelled else{return}
        let task=start(operation)
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {task.cancel()}
    }
    func cancel() {revision=UUID();work?.cancel();work=nil}
}
