use std::fs;
use std::path::PathBuf;
use clap::Parser;
use mkstorm::parser::parse;

#[derive(Parser)]
#[command(name = "mkstorm")]
#[command(about = "Invocation Language Parser", long_about = None)]
struct Cli {
    /// Input file to process
    #[arg(value_name = "FILE")]
    input: PathBuf,

    /// Optional output file (prints to stdout if not specified)
    #[arg(short, long, value_name = "OUTPUT")]
    output: Option<PathBuf>,

    /// Show debug information
    #[arg(short, long)]
    debug: bool,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    // Read input file
    let content = fs::read_to_string(&cli.input)
        .map_err(|e| format!("Error reading {}: {}", cli.input.display(), e))?;

    // Parse content
    let result = parse(&content)?;

    // Output handling
    let output = format!("{:#?}", result);
    match cli.output {
        Some(path) => fs::write(path, output)?,
        None => println!("{}", output),
    }

    Ok(())
}