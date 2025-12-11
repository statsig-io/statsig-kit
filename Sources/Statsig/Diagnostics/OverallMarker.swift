class OverallMarker: MarkerBase {
    convenience init(_ recorder: MarkerAtomicDict) {
        self.init(recorder, context: .initialize, markerKey: "overall")
    }

    func start() {
        super.start([:])
    }

    func end(success: Bool, details: EvaluationDetails, errorMessage: String?) {
        var evaluationDetailsData: [String: Any] = [
            "reason": details.getDetailedReason()
        ]

        if let lcut = details.lcut {
            evaluationDetailsData["lcut"] = lcut
        }

        if let receivedAt = details.receivedAt {
            evaluationDetailsData["receivedAt"] = receivedAt
        }

        var args: [String: Any] = [
            "success": success,
            "evaluationDetails": evaluationDetailsData,
        ]

        if let message = errorMessage {
            args["error"] = [
                "name": "Error",
                "message": message,
            ]
        }

        super.end(args)
    }
}
