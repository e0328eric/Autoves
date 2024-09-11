mod commands;

use std::ffi;
use std::fs;
use std::process::{self, Command as TermCmd, ExitCode};
use std::str;
use std::time;

use clap::Parser;

#[cfg(target_os = "windows")]
use windows::{core::*, Win32::UI::WindowsAndMessaging as win};

#[derive(Clone, Copy)]
enum LatexType {
    Plain,
    PdfLatex,
    XeLatex,
    LuaLatex,
}

fn main() -> ExitCode {
    // handling SIGINT
    unsafe {
        libc::signal(
            libc::SIGINT,
            signal_handler as *mut ffi::c_void as libc::sighandler_t,
        );
    }

    let cmd = commands::Command::parse();
    let latex_type = get_latex_type(&cmd);

    let mut first_run = true;
    let mut prev_file_modified = time::SystemTime::now();

    loop {
        let file_modified =
            match fs::metadata(&cmd.filename).and_then(|metadata| metadata.modified()) {
                Ok(modified) => modified,
                Err(err) => {
                    if cfg!(target_os = "windows") {
                        unsafe {
                            win::MessageBoxA(
                                None,
                                s!("autoves error occurs. See the console for more information"),
                                s!("autoves error"),
                                win::MB_ICONERROR | win::MB_OK,
                            )
                        };
                    }
                    eprintln!("autoves error: {err}");
                    return ExitCode::FAILURE;
                }
            };

        if first_run || file_modified > prev_file_modified {
            let argv = make_vesti_argv(&cmd.filename, latex_type);
            let output = TermCmd::new("vesti")
                .args(argv.as_slice())
                .output()
                .expect("cannot execute `vesti`");

            if !output.status.success() {
                let err_msg = format!(
                    "vesti compilation failed.\n[stdout]\n{}\n[stderr]\n{}\n",
                    std::str::from_utf8(output.stdout.as_slice()).unwrap(),
                    std::str::from_utf8(output.stderr.as_slice()).unwrap(),
                );
                if cfg!(target_os = "windows") {
                    unsafe {
                        win::MessageBoxA(
                            None,
                            PCSTR::from_raw(err_msg.as_ptr()),
                            s!("autoves warning"),
                            win::MB_ICONWARNING | win::MB_OK,
                        )
                    };
                } else {
                    eprint!("{err_msg}");
                }
            }

            println!("Press Ctrl+C to exit...");
        }

        first_run = false;
        prev_file_modified = file_modified;

        std::thread::sleep(time::Duration::from_millis(300));
    }
}

extern "C" fn signal_handler(_signal: ffi::c_int) -> ! {
    println!("exit autoves...");
    process::exit(0);
}

fn get_latex_type(cmd: &commands::Command) -> LatexType {
    if cmd.is_plain {
        LatexType::Plain
    } else if cmd.is_pdf {
        LatexType::PdfLatex
    } else if cmd.is_xe {
        LatexType::XeLatex
    } else if cmd.is_lua {
        LatexType::LuaLatex
    } else
    // TODO: There is a plan to make a configure file to change this constant
    {
        LatexType::PdfLatex
    }
}

fn make_vesti_argv(filename: &str, latex_type: LatexType) -> Vec<&str> {
    let mut output = Vec::with_capacity(10);

    output.push("compile");

    if cfg!(target_os = "windows") {
        output.push("-N");
    }

    match latex_type {
        LatexType::Plain => output.push("-L"),
        LatexType::PdfLatex => output.push("-p"),
        LatexType::XeLatex => output.push("-x"),
        LatexType::LuaLatex => output.push("-l"),
    }

    output.push(filename);

    return output;
}
