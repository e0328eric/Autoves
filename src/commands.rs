use clap::Parser;

#[derive(Parser)]
pub struct Command {
    /// file to compile
    #[arg(value_name = "FILE")]
    pub filename: String,

    /// compile with latex
    #[arg(short = 'L')]
    pub is_plain: bool,

    /// compile with pdflatex
    #[arg(short = 'p')]
    pub is_pdf: bool,

    /// compile with xelatex
    #[arg(short = 'x')]
    pub is_xe: bool,

    /// compile with lualatex
    #[arg(short = 'l')]
    pub is_lua: bool,

    /// the vesti file has a subfiles
    #[arg(short = 'S')]
    pub has_sub: bool,
}
