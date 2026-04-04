import XCTest
@testable import VoiceInputMac

final class OnlinePromptAssetsTests: XCTestCase {
    func testBuiltInGeneralPromptAssetsRenderStructuredSystemPrompt() {
        let assets = BuiltInFujianPreset.promptAssets(for: .general)

        XCTAssertTrue(assets.rolePrompt.contains("Typeless app"))
        XCTAssertTrue(assets.stylePrompt.contains("Core Rules"))
        XCTAssertTrue(assets.vocabularyPrompt.contains("OpenClaw"))
        XCTAssertTrue(assets.outputPrompt.contains("只输出优化后的纯文字"))
        XCTAssertTrue(assets.renderedSystemPromptTemplate.contains("Role: 你是 Typeless app 的极简核心"))
    }

    func testLegacySystemPromptMigratesIntoPromptAssetsWithoutLosingUserTemplate() throws {
        let json = """
        {
          "speechMode": "general",
          "optimizerSystemPromptTemplate": "旧自定义系统提示词",
          "optimizerUserPromptTemplate": "用户模板 {{TEXT}}"
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.optimizerRolePromptAsset, "旧自定义系统提示词")
        XCTAssertEqual(decoded.optimizerStylePromptAsset, "")
        XCTAssertEqual(decoded.optimizerVocabularyPromptAsset, "")
        XCTAssertEqual(decoded.optimizerOutputPromptAsset, "")
        XCTAssertEqual(decoded.optimizerUserPromptTemplate, "用户模板 {{TEXT}}")
        XCTAssertEqual(decoded.renderedOptimizerSystemPromptTemplate, "旧自定义系统提示词")
    }
}
