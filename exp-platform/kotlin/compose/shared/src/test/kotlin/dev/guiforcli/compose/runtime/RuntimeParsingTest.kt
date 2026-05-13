package dev.guiforcli.compose.runtime

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeParsingTest {
    @Test
    fun manifestWithInlinePageParsesAndLocalizes() {
        val manifest = parseManifest(
            JSONObject(
                """
                {
                  "id": "demo",
                  "displayName": "bundle.title",
                  "summary": "bundle.summary",
                  "textIcon": "🧪",
                  "pages": [
                     {
                       "id": "main",
                       "title": "pages.main.title",
                       "summary": "pages.main.summary",
                       "textIcon": "▶",
                       "sections": [
                         {
                           "id": "inputs",
                           "title": "sections.inputs.title",
                           "textIcon": "#",
                           "controls": [
                             {"id": "input", "label": "controls.input.label", "kind": "text"}
                           ],
                           "actions": [
                             {
                               "id": "run",
                               "title": "actions.run.title",
                               "textIcon": "✓",
                               "command": {"executable": "echo", "arguments": ["{{input}}"]}
                             }
                          ]
                        }
                      ]
                    }
                  ]
                }
                """.trimIndent(),
            ),
        ).localized(
            mapOf(
                "bundle.title" to "Demo",
                "bundle.summary" to "Summary",
                "pages.main.title" to "Main",
                "pages.main.summary" to "Page summary",
                "sections.inputs.title" to "Inputs",
                "controls.input.label" to "Input",
                "actions.run.title" to "Run",
            ),
        )

        assertEquals("Demo", manifest.displayName)
        assertEquals("🧪", manifest.textIcon)
        assertEquals("Main", manifest.pages.single().title)
        assertEquals("▶", manifest.pages.single().textIcon)
        assertEquals("#", manifest.pages.single().sections.single().textIcon)
        assertEquals("Input", manifest.pages.single().sections.single().controls.single().label)
        assertEquals("✓", manifest.pages.single().sections.single().actions.single().textIcon)
    }

    @Test
    fun commandRenderingOmitsOptionalGroupsWithMissingValues() {
        val command = parseManifest(
            JSONObject(
                """
                {
                  "id": "demo",
                  "displayName": "Demo",
                  "summary": "Summary",
                  "pages": [{
                    "id": "main",
                    "title": "Main",
                    "summary": "Summary",
                    "sections": [{
                      "id": "actions",
                      "actions": [{
                        "id": "run",
                        "title": "Run",
                        "command": {
                          "executable": "tool",
                          "arguments": ["--input", "{{input}}"],
                          "optionalArguments": [["--out", "{{out_dir}}"]]
                        }
                      }]
                    }]
                  }]
                }
                """.trimIndent(),
            ),
        ).pages.single().sections.single().actions.single().command

        val context = RenderContext(bundleRootPath = "/bundle", fieldValues = mapOf("input" to "reads.bam"))
        val rendered = renderCommand(command, context)

        assertEquals(listOf("--input", "reads.bam"), rendered.arguments)
        assertEquals(emptyList<String>(), missingRequiredPlaceholders(command, context))
        assertTrue(rendered.display.contains("reads.bam"))
    }
}
