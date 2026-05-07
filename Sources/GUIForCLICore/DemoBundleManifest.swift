import Foundation

public enum DemoBundleManifest {
  public static let json = """
    {
      "id": "wgs-extract",
      "displayName": "bundle.displayName",
      "summary": "bundle.summary",
      "iconName": "point.3.connected.trianglepath.dotted",
      "iconPath": "Assets/icon.png",
      "iconEmoji": "🧬",
      "sidebarIconStyle": "automatic",
      "setup": {
        "steps": [
          {
            "id": "pixi",
            "kind": "pathTool",
            "label": "setup.pixi.label",
            "value": "pixi",
            "optional": true
          },
          {
            "id": "install-wgsextract",
            "kind": "setupScript",
            "label": "setup.install-wgsextract.label",
            "value": "scripts/setup-wgsextract-pixi.sh",
            "arguments": [],
            "environment": {
              "WGSEXTRACT_INSTALL_DIR": "{{bundleRoot}}/runtime/wgsextract-cli"
            }
          },
          {
            "id": "wgse",
            "kind": "pathTool",
            "label": "setup.wgse.label",
            "value": "wgsextract",
            "optional": true
          },
          {
            "id": "deps-check",
            "kind": "pixiRun",
            "label": "setup.deps-check.label",
            "value": "deps-check",
            "workingDirectory": "runtime/wgsextract-cli/app",
            "optional": true
          }
        ]
      },
      "pages": [
        {
          "id": "workflow",
          "title": "pages.workflow.title",
          "summary": "pages.workflow.summary",
          "sections": [
            {
              "id": "workflow-overview",
              "title": "sections.workflow.workflow-overview.title",
              "subtitle": "sections.workflow.workflow-overview.subtitle",
              "controls": [
                {
                  "id": "workflow-steps",
                  "label": "controls.workflow.workflow-overview.workflow-steps.label",
                  "kind": "infoGrid",
                  "options": [
                    {
                      "id": "raw",
                      "title": "options.workflow.workflow-overview.workflow-steps.raw.title"
                    },
                    {
                      "id": "bam",
                      "title": "options.workflow.workflow-overview.workflow-steps.bam.title"
                    },
                    {
                      "id": "extract",
                      "title": "options.workflow.workflow-overview.workflow-steps.extract.title"
                    },
                    {
                      "id": "vcf",
                      "title": "options.workflow.workflow-overview.workflow-steps.vcf.title"
                    },
                    {
                      "id": "reports",
                      "title": "options.workflow.workflow-overview.workflow-steps.reports.title"
                    }
                  ]
                }
              ]
            }
          ]
        },
        {
          "id": "info-bam",
          "title": "pages.info-bam.title",
          "summary": "pages.info-bam.summary",
          "sections": [
            {
              "id": "inputs",
              "title": "sections.info-bam.inputs.title",
              "controls": [
                {
                  "id": "bam_path",
                  "label": "controls.info-bam.inputs.bam_path.label",
                  "kind": "path",
                  "tooltip": "controls.info-bam.inputs.bam_path.tooltip"
                },
                {
                  "id": "ref_path",
                  "label": "controls.info-bam.inputs.ref_path.label",
                  "kind": "path",
                  "tooltip": "controls.info-bam.inputs.ref_path.tooltip"
                },
                {
                  "id": "out_dir",
                  "label": "controls.info-bam.inputs.out_dir.label",
                  "kind": "path",
                  "tooltip": "controls.info-bam.inputs.out_dir.tooltip"
                },
                {
                  "id": "cram_version",
                  "label": "controls.info-bam.inputs.cram_version.label",
                  "kind": "dropdown",
                  "value": "3.0",
                  "tooltip": "controls.info-bam.inputs.cram_version.tooltip",
                  "options": [
                    {
                      "id": "2.1",
                      "title": "options.info-bam.inputs.cram_version.2.1.title"
                    },
                    {
                      "id": "3.0",
                      "title": "options.info-bam.inputs.cram_version.3.0.title",
                      "selected": true
                    },
                    {
                      "id": "3.1",
                      "title": "options.info-bam.inputs.cram_version.3.1.title"
                    }
                  ]
                }
              ]
            },
            {
              "id": "info-commands",
              "title": "sections.info-bam.info-commands.title",
              "actions": [
                {
                  "id": "detailed-info",
                  "title": "actions.info-bam.info-commands.detailed-info.title",
                  "tooltip": "actions.info-bam.info-commands.detailed-info.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "info",
                      "--detailed",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "clear-cache",
                  "title": "actions.info-bam.info-commands.clear-cache.title",
                  "role": "destructive",
                  "tooltip": "actions.info-bam.info-commands.clear-cache.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "clear-cache",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "calculate-coverage",
                  "title": "actions.info-bam.info-commands.calculate-coverage.title",
                  "tooltip": "actions.info-bam.info-commands.calculate-coverage.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "calculate-coverage",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "coverage-sample",
                  "title": "actions.info-bam.info-commands.coverage-sample.title",
                  "tooltip": "actions.info-bam.info-commands.coverage-sample.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "coverage-sample",
                      "{{bam_path}}"
                    ]
                  }
                }
              ]
            },
            {
              "id": "bam-commands",
              "title": "sections.info-bam.bam-commands.title",
              "actions": [
                {
                  "id": "bam-sort",
                  "title": "actions.info-bam.bam-commands.bam-sort.title",
                  "tooltip": "actions.info-bam.bam-commands.bam-sort.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "sort",
                      "{{bam_path}}",
                      "--out-dir",
                      "{{out_dir}}"
                    ]
                  }
                },
                {
                  "id": "bam-index",
                  "title": "actions.info-bam.bam-commands.bam-index.title",
                  "tooltip": "actions.info-bam.bam-commands.bam-index.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "index",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "bam-to-cram",
                  "title": "actions.info-bam.bam-commands.bam-to-cram.title",
                  "tooltip": "actions.info-bam.bam-commands.bam-to-cram.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "to-cram",
                      "{{bam_path}}",
                      "--ref",
                      "{{ref_path}}",
                      "--cram-version",
                      "{{cram_version}}"
                    ]
                  }
                },
                {
                  "id": "bam-unsort",
                  "title": "actions.info-bam.bam-commands.bam-unsort.title",
                  "tooltip": "actions.info-bam.bam-commands.bam-unsort.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "unsort",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "bam-unindex",
                  "title": "actions.info-bam.bam-commands.bam-unindex.title",
                  "role": "destructive",
                  "tooltip": "actions.info-bam.bam-commands.bam-unindex.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "unindex",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "bam-to-bam",
                  "title": "actions.info-bam.bam-commands.bam-to-bam.title",
                  "tooltip": "actions.info-bam.bam-commands.bam-to-bam.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "to-bam",
                      "{{bam_path}}",
                      "--ref",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "repair-ftdna-bam",
                  "title": "actions.info-bam.bam-commands.repair-ftdna-bam.title",
                  "tooltip": "actions.info-bam.bam-commands.repair-ftdna-bam.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "repair-ftdna-bam",
                      "{{bam_path}}"
                    ]
                  }
                }
              ]
            }
          ]
        },
        {
          "id": "extract",
          "title": "pages.extract.title",
          "summary": "pages.extract.summary",
          "sections": [
            {
              "id": "extract-inputs",
              "title": "sections.extract.extract-inputs.title",
              "controls": [
                {
                  "id": "bam_path",
                  "label": "controls.extract.extract-inputs.bam_path.label",
                  "kind": "path",
                  "tooltip": "controls.extract.extract-inputs.bam_path.tooltip"
                },
                {
                  "id": "extract_region",
                  "label": "controls.extract.extract-inputs.extract_region.label",
                  "kind": "text",
                  "placeholder": "controls.extract.extract-inputs.extract_region.placeholder",
                  "tooltip": "controls.extract.extract-inputs.extract_region.tooltip"
                },
                {
                  "id": "extract_extra",
                  "label": "controls.extract.extract-inputs.extract_extra.label",
                  "kind": "text",
                  "placeholder": "controls.extract.extract-inputs.extract_extra.placeholder",
                  "tooltip": "controls.extract.extract-inputs.extract_extra.tooltip"
                }
              ],
              "actions": [
                {
                  "id": "mito-fasta",
                  "title": "actions.extract.extract-inputs.mito-fasta.title",
                  "tooltip": "actions.extract.extract-inputs.mito-fasta.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "mito-fasta",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "mt-bam",
                  "title": "actions.extract.extract-inputs.mt-bam.title",
                  "tooltip": "actions.extract.extract-inputs.mt-bam.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "mt-bam",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "mito-vcf",
                  "title": "actions.extract.extract-inputs.mito-vcf.title",
                  "tooltip": "actions.extract.extract-inputs.mito-vcf.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "mito-vcf",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "ydna-bam",
                  "title": "actions.extract.extract-inputs.ydna-bam.title",
                  "tooltip": "actions.extract.extract-inputs.ydna-bam.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "ydna-bam",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "ydna-vcf",
                  "title": "actions.extract.extract-inputs.ydna-vcf.title",
                  "tooltip": "actions.extract.extract-inputs.ydna-vcf.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "ydna-vcf",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "y-mt-extract",
                  "title": "actions.extract.extract-inputs.y-mt-extract.title",
                  "tooltip": "actions.extract.extract-inputs.y-mt-extract.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "y-mt-extract",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "bam-subset",
                  "title": "actions.extract.extract-inputs.bam-subset.title",
                  "tooltip": "actions.extract.extract-inputs.bam-subset.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "bam-subset",
                      "{{bam_path}}",
                      "{{extract_extra}}"
                    ]
                  }
                },
                {
                  "id": "unmapped",
                  "title": "actions.extract.extract-inputs.unmapped.title",
                  "tooltip": "actions.extract.extract-inputs.unmapped.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "unmapped",
                      "{{bam_path}}"
                    ]
                  }
                },
                {
                  "id": "custom",
                  "title": "actions.extract.extract-inputs.custom.title",
                  "tooltip": "actions.extract.extract-inputs.custom.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "extract",
                      "custom",
                      "{{bam_path}}",
                      "--region",
                      "{{extract_region}}",
                      "{{extract_extra}}"
                    ]
                  }
                }
              ]
            }
          ]
        },
        {
          "id": "microarray",
          "title": "pages.microarray.title",
          "summary": "pages.microarray.summary",
          "sections": [
            {
              "id": "microarray-inputs",
              "title": "sections.microarray.microarray-inputs.title",
              "controls": [
                {
                  "id": "bam_path",
                  "label": "controls.microarray.microarray-inputs.bam_path.label",
                  "kind": "path",
                  "tooltip": "controls.microarray.microarray-inputs.bam_path.tooltip"
                },
                {
                  "id": "ref_path",
                  "label": "controls.microarray.microarray-inputs.ref_path.label",
                  "kind": "path",
                  "tooltip": "controls.microarray.microarray-inputs.ref_path.tooltip"
                }
              ]
            },
            {
              "id": "microarray-formats",
              "title": "sections.microarray.microarray-formats.title",
              "controls": [
                {
                  "id": "microarray_formats",
                  "label": "controls.microarray.microarray-formats.microarray_formats.label",
                  "kind": "checkboxGroup",
                  "options": [
                    {
                      "id": "combined-all",
                      "title": "options.microarray.microarray-formats.microarray_formats.combined-all.title",
                      "selected": true
                    },
                    {
                      "id": "23andme-v3",
                      "title": "options.microarray.microarray-formats.microarray_formats.23andme-v3.title"
                    },
                    {
                      "id": "23andme-v4",
                      "title": "options.microarray.microarray-formats.microarray_formats.23andme-v4.title"
                    },
                    {
                      "id": "23andme-v5",
                      "title": "options.microarray.microarray-formats.microarray_formats.23andme-v5.title",
                      "selected": true
                    },
                    {
                      "id": "23andme-v3-v5",
                      "title": "options.microarray.microarray-formats.microarray_formats.23andme-v3-v5.title",
                      "selected": true
                    },
                    {
                      "id": "ancestry-v1",
                      "title": "options.microarray.microarray-formats.microarray_formats.ancestry-v1.title"
                    },
                    {
                      "id": "ancestry-v2",
                      "title": "options.microarray.microarray-formats.microarray_formats.ancestry-v2.title"
                    },
                    {
                      "id": "familytreedna-v2",
                      "title": "options.microarray.microarray-formats.microarray_formats.familytreedna-v2.title"
                    },
                    {
                      "id": "familytreedna-v3",
                      "title": "options.microarray.microarray-formats.microarray_formats.familytreedna-v3.title"
                    },
                    {
                      "id": "livingdna-v1",
                      "title": "options.microarray.microarray-formats.microarray_formats.livingdna-v1.title"
                    },
                    {
                      "id": "livingdna-v2",
                      "title": "options.microarray.microarray-formats.microarray_formats.livingdna-v2.title"
                    },
                    {
                      "id": "myheritage-v1",
                      "title": "options.microarray.microarray-formats.microarray_formats.myheritage-v1.title"
                    },
                    {
                      "id": "myheritage-v2",
                      "title": "options.microarray.microarray-formats.microarray_formats.myheritage-v2.title"
                    },
                    {
                      "id": "mthfr-genetics-uk",
                      "title": "options.microarray.microarray-formats.microarray_formats.mthfr-genetics-uk.title"
                    },
                    {
                      "id": "genera-br",
                      "title": "options.microarray.microarray-formats.microarray_formats.genera-br.title"
                    },
                    {
                      "id": "meudna-br",
                      "title": "options.microarray.microarray-formats.microarray_formats.meudna-br.title"
                    },
                    {
                      "id": "aadr-1240k",
                      "title": "options.microarray.microarray-formats.microarray_formats.aadr-1240k.title"
                    },
                    {
                      "id": "human-origins-v1",
                      "title": "options.microarray.microarray-formats.microarray_formats.human-origins-v1.title"
                    },
                    {
                      "id": "reich-combined",
                      "title": "options.microarray.microarray-formats.microarray_formats.reich-combined.title"
                    }
                  ]
                }
              ],
              "actions": [
                {
                  "id": "microarray-generate",
                  "title": "actions.microarray.microarray-formats.microarray-generate.title",
                  "tooltip": "actions.microarray.microarray-formats.microarray-generate.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "microarray",
                      "--input",
                      "{{bam_path}}",
                      "--ref",
                      "{{ref_path}}",
                      "--formats",
                      "{{microarray_formats}}"
                    ]
                  }
                }
              ]
            }
          ]
        },
        {
          "id": "ancestry",
          "title": "pages.ancestry.title",
          "summary": "pages.ancestry.summary",
          "sections": [
            {
              "id": "ancestry-inputs",
              "title": "sections.ancestry.ancestry-inputs.title",
              "controls": [
                {
                  "id": "bam_path",
                  "label": "controls.ancestry.ancestry-inputs.bam_path.label",
                  "kind": "path"
                },
                {
                  "id": "yleaf_path",
                  "label": "controls.ancestry.ancestry-inputs.yleaf_path.label",
                  "kind": "path",
                  "tooltip": "controls.ancestry.ancestry-inputs.yleaf_path.tooltip"
                },
                {
                  "id": "yleaf_pos",
                  "label": "controls.ancestry.ancestry-inputs.yleaf_pos.label",
                  "kind": "path",
                  "tooltip": "controls.ancestry.ancestry-inputs.yleaf_pos.tooltip"
                },
                {
                  "id": "haplogrep_path",
                  "label": "controls.ancestry.ancestry-inputs.haplogrep_path.label",
                  "kind": "path",
                  "tooltip": "controls.ancestry.ancestry-inputs.haplogrep_path.tooltip"
                }
              ],
              "actions": [
                {
                  "id": "run-yleaf",
                  "title": "actions.ancestry.ancestry-inputs.run-yleaf.title",
                  "tooltip": "actions.ancestry.ancestry-inputs.run-yleaf.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "lineage",
                      "y-haplogroup",
                      "--bam",
                      "{{bam_path}}",
                      "--yleaf-path",
                      "{{yleaf_path}}",
                      "--pos",
                      "{{yleaf_pos}}"
                    ]
                  }
                },
                {
                  "id": "run-haplogrep",
                  "title": "actions.ancestry.ancestry-inputs.run-haplogrep.title",
                  "tooltip": "actions.ancestry.ancestry-inputs.run-haplogrep.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "lineage",
                      "mt-haplogroup",
                      "--bam",
                      "{{bam_path}}",
                      "--haplogrep-path",
                      "{{haplogrep_path}}"
                    ]
                  }
                }
              ]
            }
          ]
        },
        {
          "id": "vcf",
          "title": "pages.vcf.title",
          "summary": "pages.vcf.summary",
          "sections": [
            {
              "id": "vcf-inputs",
              "title": "sections.vcf.vcf-inputs.title",
              "controls": [
                {
                  "id": "vcf_path",
                  "label": "controls.vcf.vcf-inputs.vcf_path.label",
                  "kind": "path"
                },
                {
                  "id": "ref_path",
                  "label": "controls.vcf.vcf-inputs.ref_path.label",
                  "kind": "path"
                },
                {
                  "id": "out_dir",
                  "label": "controls.vcf.vcf-inputs.out_dir.label",
                  "kind": "path"
                }
              ]
            },
            {
              "id": "variant-calling",
              "title": "sections.vcf.variant-calling.title",
              "controls": [
                {
                  "id": "vcf_region",
                  "label": "controls.vcf.variant-calling.vcf_region.label",
                  "kind": "text",
                  "placeholder": "controls.vcf.variant-calling.vcf_region.placeholder"
                },
                {
                  "id": "vcf_gene",
                  "label": "controls.vcf.variant-calling.vcf_gene.label",
                  "kind": "text",
                  "placeholder": "controls.vcf.variant-calling.vcf_gene.placeholder"
                },
                {
                  "id": "vcf_exclude_gaps",
                  "label": "controls.vcf.variant-calling.vcf_exclude_gaps.label",
                  "kind": "toggle",
                  "value": "false"
                },
                {
                  "id": "vcf_filter_expr",
                  "label": "controls.vcf.variant-calling.vcf_filter_expr.label",
                  "kind": "text",
                  "placeholder": "controls.vcf.variant-calling.vcf_filter_expr.placeholder"
                },
                {
                  "id": "vcf_ann_vcf",
                  "label": "controls.vcf.variant-calling.vcf_ann_vcf.label",
                  "kind": "path",
                  "tooltip": "controls.vcf.variant-calling.vcf_ann_vcf.tooltip"
                }
              ],
              "actions": [
                {
                  "id": "vcf-snp",
                  "title": "actions.vcf.variant-calling.vcf-snp.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-snp.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "snp",
                      "--vcf",
                      "{{vcf_path}}",
                      "--ref",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-indel",
                  "title": "actions.vcf.variant-calling.vcf-indel.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-indel.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "indel",
                      "--vcf",
                      "{{vcf_path}}",
                      "--ref",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-sv",
                  "title": "actions.vcf.variant-calling.vcf-sv.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-sv.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "sv",
                      "--vcf",
                      "{{vcf_path}}",
                      "--ref",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-cnv",
                  "title": "actions.vcf.variant-calling.vcf-cnv.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-cnv.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "cnv",
                      "--vcf",
                      "{{vcf_path}}",
                      "--ref",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-freebayes",
                  "title": "actions.vcf.variant-calling.vcf-freebayes.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-freebayes.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "freebayes",
                      "--vcf",
                      "{{vcf_path}}",
                      "--ref",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-gatk",
                  "title": "actions.vcf.variant-calling.vcf-gatk.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-gatk.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "gatk",
                      "--vcf",
                      "{{vcf_path}}",
                      "--ref",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-deepvariant",
                  "title": "actions.vcf.variant-calling.vcf-deepvariant.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-deepvariant.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "deepvariant",
                      "--vcf",
                      "{{vcf_path}}",
                      "--ref",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-annotate",
                  "title": "actions.vcf.variant-calling.vcf-annotate.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-annotate.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "annotate",
                      "--vcf",
                      "{{vcf_path}}",
                      "--ann-vcf",
                      "{{vcf_ann_vcf}}"
                    ]
                  }
                },
                {
                  "id": "vcf-spliceai",
                  "title": "actions.vcf.variant-calling.vcf-spliceai.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-spliceai.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "spliceai",
                      "--vcf",
                      "{{vcf_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-alphamissense",
                  "title": "actions.vcf.variant-calling.vcf-alphamissense.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-alphamissense.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "alphamissense",
                      "--vcf",
                      "{{vcf_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-pharmgkb",
                  "title": "actions.vcf.variant-calling.vcf-pharmgkb.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-pharmgkb.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "pharmgkb",
                      "--vcf",
                      "{{vcf_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-filter",
                  "title": "actions.vcf.variant-calling.vcf-filter.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-filter.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "filter",
                      "--vcf",
                      "{{vcf_path}}",
                      "--filter-expr",
                      "{{vcf_filter_expr}}",
                      "--gene",
                      "{{vcf_gene}}",
                      "--region",
                      "{{vcf_region}}"
                    ]
                  }
                },
                {
                  "id": "vcf-qc",
                  "title": "actions.vcf.variant-calling.vcf-qc.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-qc.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "qc",
                      "vcf",
                      "--vcf",
                      "{{vcf_path}}"
                    ]
                  }
                },
                {
                  "id": "vcf-repair-ftdna",
                  "title": "actions.vcf.variant-calling.vcf-repair-ftdna.title",
                  "tooltip": "actions.vcf.variant-calling.vcf-repair-ftdna.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "repair-ftdna-vcf",
                      "--vcf",
                      "{{vcf_path}}"
                    ]
                  }
                }
              ]
            },
            {
              "id": "trio-analysis",
              "title": "sections.vcf.trio-analysis.title",
              "controls": [
                {
                  "id": "vcf_mother",
                  "label": "controls.vcf.trio-analysis.vcf_mother.label",
                  "kind": "path"
                },
                {
                  "id": "vcf_father",
                  "label": "controls.vcf.trio-analysis.vcf_father.label",
                  "kind": "path"
                }
              ],
              "actions": [
                {
                  "id": "vcf-trio",
                  "title": "actions.vcf.trio-analysis.vcf-trio.title",
                  "tooltip": "actions.vcf.trio-analysis.vcf-trio.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "trio",
                      "--vcf",
                      "{{vcf_path}}",
                      "--mother",
                      "{{vcf_mother}}",
                      "--father",
                      "{{vcf_father}}"
                    ]
                  }
                }
              ]
            },
            {
              "id": "vep-analysis",
              "title": "sections.vcf.vep-analysis.title",
              "controls": [
                {
                  "id": "vep_cache_path",
                  "label": "controls.vcf.vep-analysis.vep_cache_path.label",
                  "kind": "path"
                },
                {
                  "id": "vcf_vep_args",
                  "label": "controls.vcf.vep-analysis.vcf_vep_args.label",
                  "kind": "text"
                }
              ],
              "actions": [
                {
                  "id": "vcf-vep-run",
                  "title": "actions.vcf.vep-analysis.vcf-vep-run.title",
                  "tooltip": "actions.vcf.vep-analysis.vcf-vep-run.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vcf",
                      "vep-run",
                      "--vcf",
                      "{{vcf_path}}",
                      "--vep-cache",
                      "{{vep_cache_path}}",
                      "--vep-args",
                      "{{vcf_vep_args}}"
                    ]
                  }
                }
              ]
            }
          ]
        },
        {
          "id": "fastq",
          "title": "pages.fastq.title",
          "summary": "pages.fastq.summary",
          "sections": [
            {
              "id": "fastq-inputs",
              "title": "sections.fastq.fastq-inputs.title",
              "controls": [
                {
                  "id": "fastq_path",
                  "label": "controls.fastq.fastq-inputs.fastq_path.label",
                  "kind": "path"
                },
                {
                  "id": "ref_path",
                  "label": "controls.fastq.fastq-inputs.ref_path.label",
                  "kind": "path"
                },
                {
                  "id": "out_dir",
                  "label": "controls.fastq.fastq-inputs.out_dir.label",
                  "kind": "path"
                }
              ],
              "actions": [
                {
                  "id": "align",
                  "title": "actions.fastq.fastq-inputs.align.title",
                  "tooltip": "actions.fastq.fastq-inputs.align.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "align",
                      "--r1",
                      "{{fastq_path}}",
                      "--ref",
                      "{{ref_path}}",
                      "--out-dir",
                      "{{out_dir}}"
                    ]
                  }
                },
                {
                  "id": "unalign",
                  "title": "actions.fastq.fastq-inputs.unalign.title",
                  "tooltip": "actions.fastq.fastq-inputs.unalign.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "unalign",
                      "{{fastq_path}}",
                      "--out-dir",
                      "{{out_dir}}"
                    ]
                  }
                },
                {
                  "id": "fastq-index",
                  "title": "actions.fastq.fastq-inputs.fastq-index.title",
                  "tooltip": "actions.fastq.fastq-inputs.fastq-index.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "bam",
                      "index",
                      "{{fastq_path}}"
                    ]
                  }
                },
                {
                  "id": "fastqc",
                  "title": "actions.fastq.fastq-inputs.fastqc.title",
                  "tooltip": "actions.fastq.fastq-inputs.fastqc.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "qc",
                      "fastqc",
                      "--input",
                      "{{fastq_path}}"
                    ]
                  }
                },
                {
                  "id": "fastp",
                  "title": "actions.fastq.fastq-inputs.fastp.title",
                  "tooltip": "actions.fastq.fastq-inputs.fastp.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "qc",
                      "fastp",
                      "--input",
                      "{{fastq_path}}"
                    ]
                  }
                },
                {
                  "id": "fastq-vcf-qc",
                  "title": "actions.fastq.fastq-inputs.fastq-vcf-qc.title",
                  "tooltip": "actions.fastq.fastq-inputs.fastq-vcf-qc.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "qc",
                      "vcf",
                      "--input",
                      "{{fastq_path}}"
                    ]
                  }
                }
              ]
            }
          ]
        },
        {
          "id": "pet-analysis",
          "title": "pages.pet-analysis.title",
          "summary": "pages.pet-analysis.summary",
          "sections": [
            {
              "id": "pet-inputs",
              "title": "sections.pet-analysis.pet-inputs.title",
              "controls": [
                {
                  "id": "pet_species",
                  "label": "controls.pet-analysis.pet-inputs.pet_species.label",
                  "kind": "dropdown",
                  "value": "dog",
                  "options": [
                    {
                      "id": "dog",
                      "title": "options.pet-analysis.pet-inputs.pet_species.dog.title"
                    },
                    {
                      "id": "cat",
                      "title": "options.pet-analysis.pet-inputs.pet_species.cat.title"
                    }
                  ]
                },
                {
                  "id": "pet_ref_fasta",
                  "label": "controls.pet-analysis.pet-inputs.pet_ref_fasta.label",
                  "kind": "path"
                },
                {
                  "id": "out_dir",
                  "label": "controls.pet-analysis.pet-inputs.out_dir.label",
                  "kind": "path"
                },
                {
                  "id": "pet_fastq_r1",
                  "label": "controls.pet-analysis.pet-inputs.pet_fastq_r1.label",
                  "kind": "path"
                },
                {
                  "id": "pet_fastq_r2",
                  "label": "controls.pet-analysis.pet-inputs.pet_fastq_r2.label",
                  "kind": "path"
                },
                {
                  "id": "pet_output_format",
                  "label": "controls.pet-analysis.pet-inputs.pet_output_format.label",
                  "kind": "dropdown",
                  "value": "BAM",
                  "options": [
                    {
                      "id": "BAM",
                      "title": "options.pet-analysis.pet-inputs.pet_output_format.BAM.title"
                    },
                    {
                      "id": "CRAM",
                      "title": "options.pet-analysis.pet-inputs.pet_output_format.CRAM.title"
                    }
                  ]
                }
              ],
              "actions": [
                {
                  "id": "pet-align",
                  "title": "actions.pet-analysis.pet-inputs.pet-align.title",
                  "tooltip": "actions.pet-analysis.pet-inputs.pet-align.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "pet-align",
                      "--species",
                      "{{pet_species}}",
                      "--r1",
                      "{{pet_fastq_r1}}",
                      "--r2",
                      "{{pet_fastq_r2}}",
                      "--ref",
                      "{{pet_ref_fasta}}",
                      "--format",
                      "{{pet_output_format}}",
                      "--out-dir",
                      "{{out_dir}}"
                    ]
                  }
                }
              ]
            }
          ]
        },
        {
          "id": "library",
          "title": "pages.library.title",
          "summary": "pages.library.summary",
          "sections": [
            {
              "id": "library-paths",
              "title": "sections.library.library-paths.title",
              "controls": [
                {
                  "id": "ref_path",
                  "label": "controls.library.library-paths.ref_path.label",
                  "kind": "path"
                },
                {
                  "id": "vep_cache_path",
                  "label": "controls.library.library-paths.vep_cache_path.label",
                  "kind": "path"
                }
              ]
            },
            {
              "id": "genome-management",
              "title": "sections.library.genome-management.title",
              "controls": [
                {
                  "id": "reference_genome",
                  "label": "controls.library.genome-management.reference_genome.label",
                  "kind": "dropdown",
                  "value": "hs38DH",
                  "options": [
                    {
                      "id": "hs38DH",
                      "title": "options.library.genome-management.reference_genome.hs38DH.title"
                    },
                    {
                      "id": "GRCh38",
                      "title": "options.library.genome-management.reference_genome.GRCh38.title"
                    },
                    {
                      "id": "GRCh37",
                      "title": "options.library.genome-management.reference_genome.GRCh37.title"
                    },
                    {
                      "id": "T2T-CHM13",
                      "title": "options.library.genome-management.reference_genome.T2T-CHM13.title"
                    }
                  ]
                }
              ],
              "actions": [
                {
                  "id": "ref-download",
                  "title": "actions.library.genome-management.ref-download.title",
                  "tooltip": "actions.library.genome-management.ref-download.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "ref",
                      "ref-download",
                      "--name",
                      "{{reference_genome}}",
                      "--library",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "ref-index",
                  "title": "actions.library.genome-management.ref-index.title",
                  "tooltip": "actions.library.genome-management.ref-index.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "ref",
                      "ref-index",
                      "--name",
                      "{{reference_genome}}",
                      "--library",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "ref-verify",
                  "title": "actions.library.genome-management.ref-verify.title",
                  "tooltip": "actions.library.genome-management.ref-verify.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "ref",
                      "ref-verify",
                      "--name",
                      "{{reference_genome}}",
                      "--library",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "ref-count-ns",
                  "title": "actions.library.genome-management.ref-count-ns.title",
                  "tooltip": "actions.library.genome-management.ref-count-ns.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "ref",
                      "ref-count-ns",
                      "--name",
                      "{{reference_genome}}",
                      "--library",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "ref-delete",
                  "title": "actions.library.genome-management.ref-delete.title",
                  "role": "destructive",
                  "tooltip": "actions.library.genome-management.ref-delete.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "ref",
                      "ref-delete",
                      "--name",
                      "{{reference_genome}}",
                      "--library",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "ref-resume",
                  "title": "actions.library.genome-management.ref-resume.title",
                  "tooltip": "actions.library.genome-management.ref-resume.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "ref",
                      "ref-resume",
                      "--name",
                      "{{reference_genome}}",
                      "--library",
                      "{{ref_path}}"
                    ]
                  }
                }
              ]
            },
            {
              "id": "databases-tools",
              "title": "sections.library.databases-tools.title",
              "actions": [
                {
                  "id": "vep-download",
                  "title": "actions.library.databases-tools.vep-download.title",
                  "tooltip": "actions.library.databases-tools.vep-download.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vep",
                      "--download",
                      "--vep-cache",
                      "{{vep_cache_path}}"
                    ]
                  }
                },
                {
                  "id": "vep-verify",
                  "title": "actions.library.databases-tools.vep-verify.title",
                  "tooltip": "actions.library.databases-tools.vep-verify.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "vep",
                      "--verify-only",
                      "--vep-cache",
                      "{{vep_cache_path}}"
                    ]
                  }
                },
                {
                  "id": "gene-map",
                  "title": "actions.library.databases-tools.gene-map.title",
                  "tooltip": "actions.library.databases-tools.gene-map.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "ref",
                      "ref-gene-map",
                      "--library",
                      "{{ref_path}}"
                    ]
                  }
                },
                {
                  "id": "bootstrap-library",
                  "title": "actions.library.databases-tools.bootstrap-library.title",
                  "tooltip": "actions.library.databases-tools.bootstrap-library.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "ref",
                      "ref-bootstrap",
                      "--library",
                      "{{ref_path}}"
                    ]
                  }
                }
              ]
            }
          ]
        },
        {
          "id": "settings",
          "title": "pages.settings.title",
          "summary": "pages.settings.summary",
          "sections": [
            {
              "id": "settings-paths",
              "title": "sections.settings.settings-paths.title",
              "controls": [
                {
                  "id": "out_dir",
                  "label": "controls.settings.settings-paths.out_dir.label",
                  "kind": "path"
                },
                {
                  "id": "ref_path",
                  "label": "controls.settings.settings-paths.ref_path.label",
                  "kind": "path"
                },
                {
                  "id": "yleaf_path",
                  "label": "controls.settings.settings-paths.yleaf_path.label",
                  "kind": "path"
                },
                {
                  "id": "haplogrep_path",
                  "label": "controls.settings.settings-paths.haplogrep_path.label",
                  "kind": "path"
                }
              ],
              "actions": [
                {
                  "id": "save-settings",
                  "title": "actions.settings.settings-paths.save-settings.title",
                  "tooltip": "actions.settings.settings-paths.save-settings.tooltip",
                  "command": {
                    "executable": "wgse",
                    "arguments": [
                      "config",
                      "save",
                      "--out-dir",
                      "{{out_dir}}",
                      "--ref",
                      "{{ref_path}}",
                      "--yleaf-path",
                      "{{yleaf_path}}",
                      "--haplogrep-path",
                      "{{haplogrep_path}}"
                    ]
                  }
                }
              ]
            }
          ]
        }
      ]
    }
    """

  public static let stringsToml = """
    "bundle.displayName" = "WGS Extract"
    "bundle.summary" = "GUI bundle for wgsextract-cli workflows: BAM/CRAM inspection, extraction, microarray generation, ancestry, VCF analysis, FASTQ QC, pet analysis, and reference library management."
    "setup.pixi.label" = "Pixi"
    "setup.install-wgsextract.label" = "Install WGS Extract with Pixi"
    "setup.wgse.label" = "WGS Extract CLI"
    "setup.deps-check.label" = "Verify WGS Extract dependencies"
    "pages.workflow.title" = "Workflow"
    "pages.workflow.summary" = "Visualize the bioinformatics workflow from raw sequencing data to final analysis results. Hover over each milestone for the original WGS Extract guidance."
    "sections.workflow.workflow-overview.title" = "Workflow Overview"
    "sections.workflow.workflow-overview.subtitle" = "The original web GUI uses this as a clickable diagram. In this native bundle it is represented as workflow milestones."
    "controls.workflow.workflow-overview.workflow-steps.label" = "Pipeline"
    "options.workflow.workflow-overview.workflow-steps.raw.title" = "FASTQ raw reads -> alignment"
    "options.workflow.workflow-overview.workflow-steps.bam.title" = "BAM/CRAM inspection, sort, index, conversion"
    "options.workflow.workflow-overview.workflow-steps.extract.title" = "mtDNA, Y-DNA, unmapped, subset, or custom region extraction"
    "options.workflow.workflow-overview.workflow-steps.vcf.title" = "Variant calling, filtering, annotation, QC, trio, and VEP"
    "options.workflow.workflow-overview.workflow-steps.reports.title" = "Microarray, ancestry, pet, and reference-library outputs"
    "pages.info-bam.title" = "Info / BAM"
    "pages.info-bam.summary" = "BAM and CRAM are compressed files containing DNA sequences aligned to a reference genome. Use this page to identify the data build, check sequence quality, calculate coverage, or convert alignment formats."
    "sections.info-bam.inputs.title" = "Inputs"
    "controls.info-bam.inputs.bam_path.label" = "BAM/CRAM"
    "controls.info-bam.inputs.bam_path.tooltip" = "Input BAM or CRAM file."
    "controls.info-bam.inputs.ref_path.label" = "Reference (BWA)"
    "controls.info-bam.inputs.ref_path.tooltip" = "Path to the directory containing reference genomes and related files."
    "controls.info-bam.inputs.out_dir.label" = "Out Dir"
    "controls.info-bam.inputs.out_dir.tooltip" = "Directory where logs, caches, and results will be saved."
    "controls.info-bam.inputs.cram_version.label" = "Output CRAM Version"
    "controls.info-bam.inputs.cram_version.tooltip" = "Select CRAM version for BAM-to-CRAM conversion. CRAM 3.0 is recommended for GATK compatibility."
    "options.info-bam.inputs.cram_version.2.1.title" = "2.1"
    "options.info-bam.inputs.cram_version.3.0.title" = "3.0"
    "options.info-bam.inputs.cram_version.3.1.title" = "3.1"
    "sections.info-bam.info-commands.title" = "Info Commands"
    "actions.info-bam.info-commands.detailed-info.title" = "Detailed Info"
    "actions.info-bam.info-commands.detailed-info.tooltip" = "Perform a rapid analysis of your BAM/CRAM file to identify the reference genome build, file integrity, and sequencing metrics."
    "actions.info-bam.info-commands.clear-cache.title" = "Clear Info Cache"
    "actions.info-bam.info-commands.clear-cache.tooltip" = "Delete the cached .wgse_info.json for the current input file."
    "actions.info-bam.info-commands.calculate-coverage.title" = "Calc Coverage"
    "actions.info-bam.info-commands.calculate-coverage.tooltip" = "Generate a full breadth-of-coverage report. This accurately calculates how much of the genome was successfully sequenced. Time: 1-3 hours; space: 1-2 GB."
    "actions.info-bam.info-commands.coverage-sample.title" = "Sample Coverage"
    "actions.info-bam.info-commands.coverage-sample.tooltip" = "Estimate breadth of coverage using random sampling. Fast, approximate, and currently marked discontinued in wgsextract-cli."
    "sections.info-bam.bam-commands.title" = "BAM / CRAM Management"
    "actions.info-bam.bam-commands.bam-sort.title" = "Sort"
    "actions.info-bam.bam-commands.bam-sort.tooltip" = "Sort alignments by genomic coordinates. Required by most downstream tools, including variant callers."
    "actions.info-bam.bam-commands.bam-index.title" = "Index"
    "actions.info-bam.bam-commands.bam-index.tooltip" = "Create a random-access index (.bai/.crai) so tools can jump to specific regions without reading the whole file."
    "actions.info-bam.bam-commands.bam-to-cram.title" = "To CRAM"
    "actions.info-bam.bam-commands.bam-to-cram.tooltip" = "Convert BAM to CRAM for long-term storage; CRAM is usually 30-50% smaller than BAM without losing data."
    "actions.info-bam.bam-commands.bam-unsort.title" = "Unsort"
    "actions.info-bam.bam-commands.bam-unsort.tooltip" = "Mark the file as unsorted in the header. Rarely needed, but useful for tools that require a specific header state."
    "actions.info-bam.bam-commands.bam-unindex.title" = "Unindex"
    "actions.info-bam.bam-commands.bam-unindex.tooltip" = "Remove the BAM/CRAM index file to force re-indexing or clean the workspace."
    "actions.info-bam.bam-commands.bam-to-bam.title" = "To BAM"
    "actions.info-bam.bam-commands.bam-to-bam.tooltip" = "Convert CRAM back to BAM for older tools that do not support CRAM."
    "actions.info-bam.bam-commands.repair-ftdna-bam.title" = "Repair FTDNA BAM"
    "actions.info-bam.bam-commands.repair-ftdna-bam.tooltip" = "Fix Family Tree DNA BAM formatting errors that can cause failures in standard tools like GATK."
    "pages.extract.title" = "Extract"
    "pages.extract.summary" = "Extract specific subsets of DNA data, such as mitochondrial DNA, Y chromosome reads, unmapped reads, random BAM subsets, or custom regions, without processing an entire BAM/CRAM file."
    "sections.extract.extract-inputs.title" = "Inputs"
    "controls.extract.extract-inputs.bam_path.label" = "BAM/CRAM"
    "controls.extract.extract-inputs.bam_path.tooltip" = "Input BAM or CRAM file."
    "controls.extract.extract-inputs.extract_region.label" = "Region"
    "controls.extract.extract-inputs.extract_region.placeholder" = "chrM or chr1:100-200"
    "controls.extract.extract-inputs.extract_region.tooltip" = "Specify a chromosomal region such as chrM or chr1:100-200 to extract."
    "controls.extract.extract-inputs.extract_extra.label" = "Extra"
    "controls.extract.extract-inputs.extract_extra.placeholder" = "-f 0.1"
    "controls.extract.extract-inputs.extract_extra.tooltip" = "Additional parameters, such as -f 0.1 for subsetting reads."
    "actions.extract.extract-inputs.mito-fasta.title" = "MT-only FASTA"
    "actions.extract.extract-inputs.mito-fasta.tooltip" = "Extract the mitochondrial DNA consensus sequence for yFull female-only mtDNA uploads and other sequence analysis tools."
    "actions.extract.extract-inputs.mt-bam.title" = "MT-only BAM"
    "actions.extract.extract-inputs.mt-bam.tooltip" = "Isolate mitochondrial-related reads into a smaller BAM for high-resolution mtDNA analysis or Haplogrep."
    "actions.extract.extract-inputs.mito-vcf.title" = "MT-only VCF"
    "actions.extract.extract-inputs.mito-vcf.tooltip" = "Call variants specifically for mitochondrial DNA, commonly used by Mitoverse or Haplogrep."
    "actions.extract.extract-inputs.ydna-bam.title" = "Y-only BAM"
    "actions.extract.extract-inputs.ydna-bam.tooltip" = "Extract Y-chromosome reads into a separate BAM for yDNA Warehouse, yTree, and paternal lineage tools."
    "actions.extract.extract-inputs.ydna-vcf.title" = "Y-only VCF"
    "actions.extract.extract-inputs.ydna-vcf.tooltip" = "Call variants specifically for the Y chromosome, used by services like Cladefinder."
    "actions.extract.extract-inputs.y-mt-extract.title" = "Y and MT BAM"
    "actions.extract.extract-inputs.y-mt-extract.tooltip" = "Extract both Y-chromosome and mitochondrial reads into one combined BAM, recommended for male yFull WGS uploads."
    "actions.extract.extract-inputs.bam-subset.title" = "BAM Subset"
    "actions.extract.extract-inputs.bam-subset.tooltip" = "Create a smaller BAM by random read fraction, for example 0.1 for 10%, to test pipelines quickly."
    "actions.extract.extract-inputs.unmapped.title" = "Unmapped"
    "actions.extract.extract-inputs.unmapped.tooltip" = "Extract reads that did not align to the reference. Useful for investigating viral contamination or non-human DNA."
    "actions.extract.extract-inputs.custom.title" = "Custom Extract"
    "actions.extract.extract-inputs.custom.tooltip" = "Extract reads from a specific chromosomal region or gene of interest."
    "pages.microarray.title" = "Microarray"
    "pages.microarray.summary" = "Generate CombinedKit files that simulate consumer microarray raw-data formats like 23andMe, AncestryDNA, and FTDNA for upload to tools and services such as GEDmatch, Geneanet, MyHeritage, Promethease, and Genvue."
    "sections.microarray.microarray-inputs.title" = "Inputs"
    "controls.microarray.microarray-inputs.bam_path.label" = "BAM/CRAM Input"
    "controls.microarray.microarray-inputs.bam_path.tooltip" = "Input BAM or CRAM file."
    "controls.microarray.microarray-inputs.ref_path.label" = "Reference (BWA)"
    "controls.microarray.microarray-inputs.ref_path.tooltip" = "Path to the directory containing reference genomes and related files."
    "sections.microarray.microarray-formats.title" = "Target Formats"
    "controls.microarray.microarray-formats.microarray_formats.label" = "Formats"
    "options.microarray.microarray-formats.microarray_formats.combined-all.title" = "Combined ALL SNPs (GEDMATCH)"
    "options.microarray.microarray-formats.microarray_formats.23andme-v3.title" = "23andMe v3"
    "options.microarray.microarray-formats.microarray_formats.23andme-v4.title" = "23andMe v4"
    "options.microarray.microarray-formats.microarray_formats.23andme-v5.title" = "23andMe v5"
    "options.microarray.microarray-formats.microarray_formats.23andme-v3-v5.title" = "23andMe v3+v5"
    "options.microarray.microarray-formats.microarray_formats.ancestry-v1.title" = "AncestryDNA v1"
    "options.microarray.microarray-formats.microarray_formats.ancestry-v2.title" = "AncestryDNA v2"
    "options.microarray.microarray-formats.microarray_formats.familytreedna-v2.title" = "FamilyTreeDNA v2"
    "options.microarray.microarray-formats.microarray_formats.familytreedna-v3.title" = "FamilyTreeDNA v3"
    "options.microarray.microarray-formats.microarray_formats.livingdna-v1.title" = "Living DNA v1"
    "options.microarray.microarray-formats.microarray_formats.livingdna-v2.title" = "Living DNA v2"
    "options.microarray.microarray-formats.microarray_formats.myheritage-v1.title" = "MyHeritage v1"
    "options.microarray.microarray-formats.microarray_formats.myheritage-v2.title" = "MyHeritage v2"
    "options.microarray.microarray-formats.microarray_formats.mthfr-genetics-uk.title" = "MTHFR Genetics UK"
    "options.microarray.microarray-formats.microarray_formats.genera-br.title" = "Genera BR"
    "options.microarray.microarray-formats.microarray_formats.meudna-br.title" = "meuDNA BR"
    "options.microarray.microarray-formats.microarray_formats.aadr-1240k.title" = "AADR 1240K"
    "options.microarray.microarray-formats.microarray_formats.human-origins-v1.title" = "Human Origins v1"
    "options.microarray.microarray-formats.microarray_formats.reich-combined.title" = "Reich Combined"
    "actions.microarray.microarray-formats.microarray-generate.title" = "Generate CombinedKit"
    "actions.microarray.microarray-formats.microarray-generate.tooltip" = "Simulate consumer microarray files from WGS data for formats such as 23andMe, AncestryDNA, and FTDNA."
    "pages.ancestry.title" = "Ancestry"
    "pages.ancestry.summary" = "Identify haplogroups and deep ancestral lineages. Yleaf tracks paternal Y-DNA descent, while Haplogrep tracks maternal mitochondrial descent based on markers in your DNA."
    "sections.ancestry.ancestry-inputs.title" = "Inputs"
    "controls.ancestry.ancestry-inputs.bam_path.label" = "BAM/CRAM"
    "controls.ancestry.ancestry-inputs.yleaf_path.label" = "Yleaf Path"
    "controls.ancestry.ancestry-inputs.yleaf_path.tooltip" = "Path to the Yleaf executable for Y-haplogroup prediction."
    "controls.ancestry.ancestry-inputs.yleaf_pos.label" = "Pos File"
    "controls.ancestry.ancestry-inputs.yleaf_pos.tooltip" = "Yleaf position file, for example data/yleaf/pos.txt."
    "controls.ancestry.ancestry-inputs.haplogrep_path.label" = "Haplogrep Path"
    "controls.ancestry.ancestry-inputs.haplogrep_path.tooltip" = "Path to the Haplogrep JAR or executable for mitochondrial lineage prediction."
    "actions.ancestry.ancestry-inputs.run-yleaf.title" = "Run Yleaf"
    "actions.ancestry.ancestry-inputs.run-yleaf.tooltip" = "Predict paternal haplogroup using Yleaf. Requires a BAM with Y-chromosome reads."
    "actions.ancestry.ancestry-inputs.run-haplogrep.title" = "Run Haplogrep"
    "actions.ancestry.ancestry-inputs.run-haplogrep.tooltip" = "Predict maternal haplogroup using Haplogrep. Requires a BAM with mitochondrial reads."
    "pages.vcf.title" = "VCF"
    "pages.vcf.summary" = "VCF files list positions where DNA differs from the reference genome. Use this page to call SNPs, InDels, structural variants, and CNVs; annotate or filter variants; perform trio analysis; and run VEP."
    "sections.vcf.vcf-inputs.title" = "Inputs"
    "controls.vcf.vcf-inputs.vcf_path.label" = "VCF Input"
    "controls.vcf.vcf-inputs.ref_path.label" = "Reference Library"
    "controls.vcf.vcf-inputs.out_dir.label" = "Out Dir"
    "sections.vcf.variant-calling.title" = "Variant Calling & Annotation"
    "controls.vcf.variant-calling.vcf_region.label" = "Region"
    "controls.vcf.variant-calling.vcf_region.placeholder" = "chrM, chr1:100-200"
    "controls.vcf.variant-calling.vcf_gene.label" = "Gene Name"
    "controls.vcf.variant-calling.vcf_gene.placeholder" = "BRCA1"
    "controls.vcf.variant-calling.vcf_exclude_gaps.label" = "Gap-Aware Filtering"
    "controls.vcf.variant-calling.vcf_filter_expr.label" = "Filter Expr"
    "controls.vcf.variant-calling.vcf_filter_expr.placeholder" = "QUAL>30 && DP>10"
    "controls.vcf.variant-calling.vcf_ann_vcf.label" = "Annotate VCF"
    "controls.vcf.variant-calling.vcf_ann_vcf.tooltip" = "VCF file to use for annotation, such as ClinVar or dbSNP."
    "actions.vcf.variant-calling.vcf-snp.title" = "SNP Call"
    "actions.vcf.variant-calling.vcf-snp.tooltip" = "Call Single Nucleotide Polymorphisms with bcftools for ancestry analysis and point mutations."
    "actions.vcf.variant-calling.vcf-indel.title" = "InDel Call"
    "actions.vcf.variant-calling.vcf-indel.tooltip" = "Call small insertions and deletions with bcftools."
    "actions.vcf.variant-calling.vcf-sv.title" = "SV Call"
    "actions.vcf.variant-calling.vcf-sv.tooltip" = "Call structural variants using Delly, or pbsv for PacBio long-read alignments."
    "actions.vcf.variant-calling.vcf-cnv.title" = "CNV Call"
    "actions.vcf.variant-calling.vcf-cnv.tooltip" = "Call copy-number variants using Delly. Detects duplicated or deleted DNA regions."
    "actions.vcf.variant-calling.vcf-freebayes.title" = "Freebayes"
    "actions.vcf.variant-calling.vcf-freebayes.tooltip" = "Run Freebayes, a Bayesian variant detector that works well in complex regions or variable depth."
    "actions.vcf.variant-calling.vcf-gatk.title" = "GATK HC"
    "actions.vcf.variant-calling.vcf-gatk.tooltip" = "Run GATK HaplotypeCaller, an industry-standard high-accuracy SNP/InDel caller."
    "actions.vcf.variant-calling.vcf-deepvariant.title" = "DeepVariant"
    "actions.vcf.variant-calling.vcf-deepvariant.tooltip" = "Run Google's DeepVariant neural-network caller for WGS/WES and PacBio HiFi models."
    "actions.vcf.variant-calling.vcf-annotate.title" = "Annotate"
    "actions.vcf.variant-calling.vcf-annotate.tooltip" = "Add external metadata such as population frequencies or disease risk to a VCF."
    "actions.vcf.variant-calling.vcf-spliceai.title" = "SpliceAI"
    "actions.vcf.variant-calling.vcf-spliceai.tooltip" = "Annotate VCF with SpliceAI scores that predict whether variants disrupt RNA splicing."
    "actions.vcf.variant-calling.vcf-alphamissense.title" = "AlphaMissense"
    "actions.vcf.variant-calling.vcf-alphamissense.tooltip" = "Annotate VCF with AlphaMissense pathogenicity scores based on protein-structure predictions."
    "actions.vcf.variant-calling.vcf-pharmgkb.title" = "PharmGKB"
    "actions.vcf.variant-calling.vcf-pharmgkb.tooltip" = "Annotate VCF with PharmGKB drug metabolism data."
    "actions.vcf.variant-calling.vcf-filter.title" = "Filter"
    "actions.vcf.variant-calling.vcf-filter.tooltip" = "Filter variant calls by quality, region, or gene to focus on relevant results."
    "actions.vcf.variant-calling.vcf-qc.title" = "VCF QC"
    "actions.vcf.variant-calling.vcf-qc.tooltip" = "Generate statistical reports for a VCF to inspect variant-call quality and distribution."
    "actions.vcf.variant-calling.vcf-repair-ftdna.title" = "Repair FTDNA VCF"
    "actions.vcf.variant-calling.vcf-repair-ftdna.tooltip" = "Fix formatting errors in FTDNA VCF files to make them compatible with modern annotation tools like VEP."
    "sections.vcf.trio-analysis.title" = "Trio Analysis"
    "controls.vcf.trio-analysis.vcf_mother.label" = "Mother VCF"
    "controls.vcf.trio-analysis.vcf_father.label" = "Father VCF"
    "actions.vcf.trio-analysis.vcf-trio.title" = "Run Trio"
    "actions.vcf.trio-analysis.vcf-trio.tooltip" = "Compare child and parent VCFs to identify de novo mutations or inherited conditions."
    "sections.vcf.vep-analysis.title" = "VEP Analysis"
    "controls.vcf.vep-analysis.vep_cache_path.label" = "VEP Cache"
    "controls.vcf.vep-analysis.vcf_vep_args.label" = "Extra VEP Args"
    "actions.vcf.vep-analysis.vcf-vep-run.title" = "Run VEP"
    "actions.vcf.vep-analysis.vcf-vep-run.tooltip" = "Run Ensembl Variant Effect Predictor to predict functional impact, such as gene disruption or disease relevance."
    "pages.fastq.title" = "FASTQ"
    "pages.fastq.summary" = "FASTQ files contain raw sequencer reads before alignment. Use this page to run FastQC/FastP, align raw reads to a reference genome, create BAM/CRAM files, or extract FASTQ from alignments."
    "sections.fastq.fastq-inputs.title" = "Inputs"
    "controls.fastq.fastq-inputs.fastq_path.label" = "FASTQ / BAM"
    "controls.fastq.fastq-inputs.ref_path.label" = "Reference Library"
    "controls.fastq.fastq-inputs.out_dir.label" = "Out Dir"
    "actions.fastq.fastq-inputs.align.title" = "Run Align"
    "actions.fastq.fastq-inputs.align.tooltip" = "Map raw FASTQ reads to a reference genome to create an aligned BAM/CRAM file."
    "actions.fastq.fastq-inputs.unalign.title" = "Unalign"
    "actions.fastq.fastq-inputs.unalign.tooltip" = "Extract raw reads from BAM/CRAM back into FASTQ for re-alignment to another reference."
    "actions.fastq.fastq-inputs.fastq-index.title" = "Index"
    "actions.fastq.fastq-inputs.fastq-index.tooltip" = "Create an index for the generated alignment file."
    "actions.fastq.fastq-inputs.fastqc.title" = "FastQC"
    "actions.fastq.fastq-inputs.fastqc.tooltip" = "Run FastQC quality checks for base quality, GC content, and adapter contamination."
    "actions.fastq.fastq-inputs.fastp.title" = "FastP"
    "actions.fastq.fastq-inputs.fastp.tooltip" = "Run fastp to trim adapters, filter low-quality reads, and generate a QC report."
    "actions.fastq.fastq-inputs.fastq-vcf-qc.title" = "VCF QC"
    "actions.fastq.fastq-inputs.fastq-vcf-qc.tooltip" = "Run VCF quality-control statistics after FASTQ-derived variant calling."
    "pages.pet-analysis.title" = "Pet Analysis"
    "pages.pet-analysis.summary" = "Analyze pet DNA data by aligning raw FASTQ reads against dog or cat reference genomes and generating variant calls with standard bioinformatics tools."
    "sections.pet-analysis.pet-inputs.title" = "Pet Inputs"
    "controls.pet-analysis.pet-inputs.pet_species.label" = "Pet Species"
    "options.pet-analysis.pet-inputs.pet_species.dog.title" = "Dog"
    "options.pet-analysis.pet-inputs.pet_species.cat.title" = "Cat"
    "controls.pet-analysis.pet-inputs.pet_ref_fasta.label" = "Reference Genome"
    "controls.pet-analysis.pet-inputs.out_dir.label" = "Out Dir"
    "controls.pet-analysis.pet-inputs.pet_fastq_r1.label" = "FASTQ R1"
    "controls.pet-analysis.pet-inputs.pet_fastq_r2.label" = "FASTQ R2 (optional)"
    "controls.pet-analysis.pet-inputs.pet_output_format.label" = "Output Format"
    "options.pet-analysis.pet-inputs.pet_output_format.BAM.title" = "BAM"
    "options.pet-analysis.pet-inputs.pet_output_format.CRAM.title" = "CRAM"
    "actions.pet-analysis.pet-inputs.pet-align.title" = "Align Pet FASTQ"
    "actions.pet-analysis.pet-inputs.pet-align.tooltip" = "Align dog or cat FASTQ reads against the selected species reference and call variants."
    "pages.library.title" = "Library"
    "pages.library.summary" = "Manage reference data: standardized reference genomes, indexes, gene maps, annotation datasets, and VEP caches used by alignment and advanced variant-effect workflows."
    "sections.library.library-paths.title" = "Library Paths"
    "controls.library.library-paths.ref_path.label" = "Reference Library Path"
    "controls.library.library-paths.vep_cache_path.label" = "VEP Cache Path"
    "sections.library.genome-management.title" = "Manage Genomes"
    "controls.library.genome-management.reference_genome.label" = "Reference Genome"
    "options.library.genome-management.reference_genome.hs38DH.title" = "hs38DH"
    "options.library.genome-management.reference_genome.GRCh38.title" = "GRCh38"
    "options.library.genome-management.reference_genome.GRCh37.title" = "GRCh37"
    "options.library.genome-management.reference_genome.T2T-CHM13.title" = "T2T-CHM13"
    "actions.library.genome-management.ref-download.title" = "Download"
    "actions.library.genome-management.ref-download.tooltip" = "Download curated standard reference genomes such as hg19, hg38, or T2T."
    "actions.library.genome-management.ref-index.title" = "Index"
    "actions.library.genome-management.ref-index.tooltip" = "Index a FASTA reference so it can be used for alignment and variant calling."
    "actions.library.genome-management.ref-verify.title" = "Verify"
    "actions.library.genome-management.ref-verify.tooltip" = "Verify a reference genome and its companion files for corruption or missing indexes."
    "actions.library.genome-management.ref-count-ns.title" = "Count-Ns"
    "actions.library.genome-management.ref-count-ns.tooltip" = "Count unknown N bases in a genome to assess mappability and support gap-aware filtering."
    "actions.library.genome-management.ref-delete.title" = "Delete"
    "actions.library.genome-management.ref-delete.tooltip" = "Delete a selected reference genome from the local library."
    "actions.library.genome-management.ref-resume.title" = "Resume"
    "actions.library.genome-management.ref-resume.tooltip" = "Resume an interrupted reference download."
    "sections.library.databases-tools.title" = "Databases & Tools"
    "actions.library.databases-tools.vep-download.title" = "Download VEP Cache"
    "actions.library.databases-tools.vep-download.tooltip" = "Download the VEP cache for local offline annotation."
    "actions.library.databases-tools.vep-verify.title" = "Verify VEP Cache"
    "actions.library.databases-tools.vep-verify.tooltip" = "Verify the local VEP cache for missing files or corruption."
    "actions.library.databases-tools.gene-map.title" = "Gene Map"
    "actions.library.databases-tools.gene-map.tooltip" = "Download or delete lightweight gene-to-coordinate maps for filtering VCFs by gene name."
    "actions.library.databases-tools.bootstrap-library.title" = "Bootstrap Library"
    "actions.library.databases-tools.bootstrap-library.tooltip" = "Download and initialize the reference-library bootstrap assets such as VCFs, chains, and support data."
    "pages.settings.title" = "Settings"
    "pages.settings.summary" = "Configure default output, reference library, Yleaf, and Haplogrep paths used by WGS Extract workflows."
    "sections.settings.settings-paths.title" = "Global Paths"
    "controls.settings.settings-paths.out_dir.label" = "Output Directory"
    "controls.settings.settings-paths.ref_path.label" = "Reference Library"
    "controls.settings.settings-paths.yleaf_path.label" = "Yleaf Execution Path"
    "controls.settings.settings-paths.haplogrep_path.label" = "Haplogrep JAR Path"
    "actions.settings.settings-paths.save-settings.title" = "Save Settings"
    "actions.settings.settings-paths.save-settings.tooltip" = "Save the current default output, reference, Yleaf, and Haplogrep paths."
    """

  public static let wgsExtractPixiSetupScript = """
    #!/bin/sh
    set -eu

    REPO_URL="${WGSEXTRACT_REPO_URL:-}"
    REQUESTED_REF="${WGSEXTRACT_REF:-${WGSEXTRACT_RELEASE_TAG:-latest}}"
    INSTALL_DIR="${WGSEXTRACT_INSTALL_DIR:-$(pwd)/runtime/wgsextract-cli}"
    APP_DIR="$INSTALL_DIR/app"
    PIXI_CACHE_DIR="${WGSEXTRACT_PIXI_CACHE_DIR:-$INSTALL_DIR/.pixi/cache}"
    PIXI_ENV_DIR="${WGSEXTRACT_PIXI_ENV_DIR:-$INSTALL_DIR/.pixi/envs}"

    log() { printf '%s\\n' "$*"; }
    fail() { printf 'Error: %s\\n' "$*" >&2; exit 1; }
    command_exists() { command -v "$1" >/dev/null 2>&1; }

    command_exists curl || fail "curl is required."
    command_exists tar || fail "tar is required."
    command_exists gzip || fail "gzip is required."

    PIXI="${PIXI:-}"
    if [ -n "$PIXI" ] && [ ! -x "$PIXI" ]; then
      fail "PIXI is set but is not executable: $PIXI"
    fi
    if [ -z "$PIXI" ]; then
      if command_exists pixi; then
        PIXI="$(command -v pixi)"
      elif [ -x "$HOME/.pixi/bin/pixi" ]; then
        PIXI="$HOME/.pixi/bin/pixi"
      else
        log "Installing Pixi..."
        curl -fsSL https://pixi.sh/install.sh | sh
        if [ -x "$HOME/.pixi/bin/pixi" ]; then
          PIXI="$HOME/.pixi/bin/pixi"
        elif command_exists pixi; then
          PIXI="$(command -v pixi)"
        else
          fail "Pixi installation completed, but pixi was not found."
        fi
      fi
    fi

    if [ "${WGSEXTRACT_ARCHIVE_URL:-}" ]; then
      ARCHIVE_URL="$WGSEXTRACT_ARCHIVE_URL"
    else
      [ -n "$REPO_URL" ] || fail "Set WGSEXTRACT_REPO_URL or WGSEXTRACT_ARCHIVE_URL before running setup."
      if [ "$REQUESTED_REF" = "latest" ] || [ -z "$REQUESTED_REF" ]; then
        latest_url="$REPO_URL/releases/latest"
        effective_url="$(curl -fsIL -o /dev/null -w '%{url_effective}' "$latest_url")" || fail "Could not resolve latest release."
        REF="${effective_url##*/}"
      else
        REF="$REQUESTED_REF"
      fi
      ARCHIVE_URL="$REPO_URL/archive/$REF.tar.gz"
    fi

    mkdir -p "$INSTALL_DIR/tmp" "$PIXI_CACHE_DIR" "$PIXI_ENV_DIR"
    work_dir="$(mktemp -d "$INSTALL_DIR/tmp/install.XXXXXX")"
    trap 'rm -rf "$work_dir"' EXIT INT HUP TERM
    archive="$work_dir/wgsextract-cli.tar.gz"
    extract_dir="$work_dir/source"
    mkdir -p "$extract_dir"

    log "Downloading WGS Extract CLI from $ARCHIVE_URL"
    curl -fL --retry 3 --retry-delay 2 -o "$archive" "$ARCHIVE_URL"
    tar -xzf "$archive" -C "$extract_dir"
    source_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$source_dir" ] || fail "Downloaded archive did not contain a source directory."

    rm -rf "$APP_DIR.new"
    mkdir -p "$INSTALL_DIR"
    mv "$source_dir" "$APP_DIR.new"
    rm -rf "$APP_DIR"
    mv "$APP_DIR.new" "$APP_DIR"

    log "Installing Pixi environment..."
    cd "$APP_DIR"
    export PIXI_CACHE_DIR
    export PIXI_PROJECT_ENVIRONMENT_DIR="$PIXI_ENV_DIR"
    "$PIXI" install
    "$PIXI" run wgsextract --help >/dev/null
    "$PIXI" run wgsextract deps check

    log "WGS Extract CLI is installed in $INSTALL_DIR"
    """
}
