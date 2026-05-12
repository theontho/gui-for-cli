use anyhow::{Context, Result, anyhow};
use std::env;
use std::path::{Path, PathBuf};

#[derive(Debug, Default)]
pub struct Args {
    pub bundle: PathBuf,
    pub repo_root: PathBuf,
    pub locale: String,
    pub benchmark: bool,
    pub benchmark_full: bool,
    pub once: bool,
}

pub fn parse_args() -> Result<Args> {
    let current_dir = env::current_dir().context("read current directory")?;
    let repo_root = find_repo_root(&current_dir).unwrap_or(current_dir);
    let mut args = Args {
        bundle: default_bundle_path(&repo_root),
        repo_root,
        locale: "en".to_string(),
        benchmark: false,
        benchmark_full: false,
        once: false,
    };
    let mut bundle_was_provided = false;

    let mut raw = env::args().skip(1);
    while let Some(argument) = raw.next() {
        match argument.as_str() {
            "--bundle" => {
                bundle_was_provided = true;
                args.bundle = PathBuf::from(
                    raw.next()
                        .ok_or_else(|| anyhow!("--bundle requires a path"))?,
                );
            }
            "--repo-root" => {
                args.repo_root = PathBuf::from(
                    raw.next()
                        .ok_or_else(|| anyhow!("--repo-root requires a path"))?,
                );
                if !bundle_was_provided {
                    args.bundle = default_bundle_path(&args.repo_root);
                }
            }
            "--locale" => {
                args.locale = raw
                    .next()
                    .ok_or_else(|| anyhow!("--locale requires a locale code"))?;
            }
            "--benchmark" => args.benchmark = true,
            "--benchmark-full" => {
                args.benchmark = true;
                args.benchmark_full = true;
            }
            "--once" => args.once = true,
            "--version" | "-V" => {
                println!("gui-for-cli-slint {}", env!("CARGO_PKG_VERSION"));
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

pub fn configure_default_renderer() {
    if env::var_os("SLINT_BACKEND").is_none() {
        // SAFETY: this runs before the Slint window starts and before this process creates threads.
        unsafe {
            env::set_var("SLINT_BACKEND", "winit-software");
        }
    }
}

fn print_help() {
    println!(
        "Usage: gui-for-cli-slint [--bundle PATH] [--repo-root PATH] [--locale CODE] [--benchmark] [--benchmark-full] [--once] [--version]"
    );
}

fn find_repo_root(start: &Path) -> Option<PathBuf> {
    start
        .ancestors()
        .find(|candidate| candidate.join("Examples").join("WGSExtract").exists())
        .map(Path::to_path_buf)
}

fn default_bundle_path(repo_root: &Path) -> PathBuf {
    repo_root.join("Examples").join("WGSExtract")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_bundle_comes_from_final_repo_root() {
        let repo_root = PathBuf::from("/tmp/gui-for-cli");

        assert_eq!(
            default_bundle_path(&repo_root),
            PathBuf::from("/tmp/gui-for-cli/Examples/WGSExtract")
        );
    }
}
