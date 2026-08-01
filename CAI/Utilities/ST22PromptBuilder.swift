import Foundation

/// Builds the templated instruction sent to the backend when the user asks
/// to decode an ST22 short dump (bluefunda/cai-ios#182) — either pasted as
/// text or attached as a screenshot. Kept separate from what's shown in the
/// user's own chat bubble, which stays exactly what they pasted/typed.
enum ST22PromptBuilder {
    static func buildPrompt(rawDump: String?) -> String {
        let source = rawDump != nil
            ? "Using the dump below, respond"
            : "Using the attached ST22 dump screenshot, respond"

        var prompt = """
        You are analyzing an SAP ST22 ABAP runtime error (short dump). \(source) \
        in three clearly labeled Markdown sections:

        ## Root Cause
        Explain what triggered this dump and identify the offending code or \
        configuration.

        ## Suggested Fix
        Concrete steps or code/config changes to resolve it.

        ## References
        Any relevant SAP OSS Notes you know of; otherwise say none are known.
        """

        if let rawDump {
            prompt += "\n\nDump:\n\(rawDump)"
        }

        return prompt
    }
}
