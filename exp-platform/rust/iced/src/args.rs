use anyhow::{Context, Result, anyhow};
use std::env;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub struct Args {
    pub bundle: PathBuf,
    pub repo_root: PathBuf,
    pub locale: String,
    pub check: bool,
    pub benchmark: bool,
    pub benchmark_full: bool,
    pub once: bool,
    pub benchmark_output: Option<PathBuf>,
}

pub fn parse_args() -> Result<Args> {
    let current_dir = env::current_dir().context("read current directory")?;
    let repo_root = find_repo_root(&current_dir).unwrap_or(current_dir);
    let mut args = Args {
        bundle: default_bundle_path(&repo_root),
        repo_root,
        locale: "en".to_string(),
        check: false,
        benchmark: false,
        benchmark_full: false,
        once: false,
        benchmark_output: None,
    };
    let mut bundle_was_provided = false;

    let mut raw = env::args().skip(1);
    while let Some(argument) = raw.next() {
        match argument.as_str() {
            "--bundle" => {
                bundle_was_provided = true;
                args.bundle = PathBuf::from(next_option_value(&mut raw, "--bundle")?);
            }
            "--repo-root" => {
                args.repo_root = PathBuf::from(next_option_value(&mut raw, "--repo-root")?);
                if !bundle_was_provided {
                    args.bundle = default_bundle_path(&args.repo_root);
                }
            }
            "--locale" => args.locale = next_option_value(&mut raw, "--locale")?,
            "--check" => args.check = true,
            "--benchmark" => args.benchmark = true,
            "--benchmark-full" => {
                args.benchmark = true;
                args.benchmark_full = true;
            }
            "--once" => args.once = true,
            "--benchmark-output" => {
                args.benchmark_output = Some(PathBuf::from(next_option_value(
                    &mut raw,
                    "--benchmark-output",
                )?));
            }
            "--version" | "-V" => {
                println!("gui-for-cli-iced {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            "--help" | "-h" => {
                print_help();
                std::process::exit(0);
            }
            _ => return Err(anyhow!("unknown argument: {argument}")),
        }
    }

    if args.bundle.is_relative() {
        args.bundle = args.repo_root.join(&args.bundle);
    }
    Ok(args)
}

fn next_option_value(raw: &mut impl Iterator<Item = String>, flag: &str) -> Result<String> {
    let value = raw
        .next()
        .ok_or_else(|| anyhow!("{flag} requires a value"))?;
    if value.starts_with('-') {
        return Err(anyhow!("{flag} requires a value"));
    }
    Ok(value)
}

fn print_help() {
    println!(
        "Usage: gui-for-cli-iced [--bundle PATH] [--repo-root PATH] [--locale CODE] [--check] [--benchmark] [--benchmark-full] [--once] [--benchmark-output PATH] [--version]"
    );
}

fn find_repo_root(start: &Path) -> Option<PathBuf> {
    start
        .ancestors()
        .find(|candidate| candidate.join("examples").join("WGSExtract").exists())
        .map(Path::to_path_buf)
}

fn default_bundle_path(repo_root: &Path) -> PathBuf {
    repo_root.join("examples").join("WGSExtract")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_bundle_comes_from_final_repo_root() {
        let repo_root = PathBuf::from("/repo/gui-for-cli");

        assert_eq!(
            default_bundle_path(&repo_root),
            PathBuf::from("/repo/gui-for-cli/examples/WGSExtract")
        );
    }

    #[test]
    fn option_values_reject_flag_tokens() {
        let mut raw = vec!["--once".to_string()].into_iter();

        let error = next_option_value(&mut raw, "--locale").expect_err("flag token should fail");

        assert!(error.to_string().contains("--locale requires a value"));
    }
}
