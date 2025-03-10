﻿namespace ClangPowerTools.MVVM
{
  public class SettingsTooltips
  {
    #region Compile
    public string CompileFlags { get; } = "Flags given to clang++ when compiling project, alongside project - specific defines. If empty the default flags will be loaded.";
    public string FilesToIgnoreCompile { get; } = "Array of file(s) to ignore, from the matched ones. If empty, all already matched files are compiled.";
    public string ProjectsToIgnore { get; } = "Array of project(s) to ignore, from the matched ones. If empty, all already matched projects are compiled.";
    public string AdditionalIncludes { get; } = "Specify how clang interprets project additional include directories: as regular includes(-I) or system includes (-isystem ).";
    public string WarningsAsErrors { get; } = "Treats all compiler warnings as errors. For a new project, it may be best to use in all compilations; resolving all warnings will ensure the fewest possible hard to find code defects.";
    public string ContinueOnError { get; } = "Switch to continue project compilation even when errors occur.";
    public string ClangAfterMSVC { get; } = "Automatically run Clang compile on the current source file, after successful MSVC compilation.";
    public string VerboseMode { get; } = "Enables verbose logging for diagnostic purposes.";
    public string ShowErrorList { get; } = "Always show Error List if Clang compile/tidy finishes with errors.";
    public string ShowOutputWindow { get; } = "Always show Output window after Clang compile/tidy or when any Clang Power Tools information message occurs.";
    public string ShowSquiggles { get; } = "Show squiggles for every suggestion generated by Clang.";
    public string CpuLimit { get; } = "Limit the number of cores for compile, tidy and tidy-fix";

    #endregion

    #region Tidy

    public string HeaderFilter { get; } = "Regular expression matching the names of the headers to output diagnostics from. Diagnostics from the source file are always displayed." +
      "This option overrides the 'HeaderFilterRegex' option in .clang-tidy file, if any.\n" +
      "\"Corresponding Header\" : output diagnostics/fix only the corresponding header (same filename) for each source file analyzed.";

    public string UseChecksFrom { get; } = "Tidy checks: switch between explicitly specified checks (predefined or custom) and using checks from .clang-tidy configuration files.\n" +
      "Other options are always loaded from .clang-tidy files.";

    public string PredefinedChecks { get; } = "A list of clang-tidy static analyzer and diagnostics checks from LLVM.";
    public string CustomChecks { get; } = "Specify clang-tidy checks to run using the standard tidy syntax. You can use wildcards to match multiple checks, combine them, etc (Eg. \"modernize-*, readability-*\").";
    public string CustomExecutableTidy { get; } = "Specify a custom path for \"clang-tidy.exe\" file to run instead of the built-in one (v8.0).";
    public string DetectClangTidyFile { get; } = "Automatically detect the \".clang-tidy\" file and set the \"Use checks from\" option to \"TidyFile\" if the file exists. Otherwise, set the \"Use checks from\" option to \"PredefinedChecks\".";
    public string FormatAfterTidy { get; } = "Automatically run clang-format after clang-tidy finished.";
    public string TidyOnSave { get; } = "Automatically run clang-tidy when saving the current source file.";
    public string ApplyTidyFix { get; } = "Replace Tidy with Tidy-Fix, in context menu and toolbar";
    public string TidyFileConfig { get; } = "Export tidy options into a \".clang-tidy\" config file.";

    #endregion

    #region Format

    public string FileExtensions { get; } = "When formatting on save, clang-format will be applied only to files with these extensions.";
    public string FilesToIgnoreFormat { get; } = "When formatting on save, clang-format will not be applied on these files.";
    public string AssumeFilename { get; } = "When reading from stdin, clang-format assumes this filename to look for a style config file (with -style=file) and to determine the language.";
    public string CustomExecutableFormat { get; } = "Specify a custom path for \"clang-format.exe\" file to run instead of the built-in one.";

    public string Style { get; } = "Coding style, currently supports: LLVM, Google, Chromium, Mozilla, WebKit.\nUse -style=file to load " +
      "style configuration from .clang-format file located in one of the parent directories of the " +
      "source file(or current directory for stdin).\nUse -style=\"{key: value, ...}\" to set specific parameters, " +
      "e.g.: -style=\"{BasedOnStyle: llvm, IndentWidth: 8}\".";

    public string FallbackStyle { get; } = "The name of the predefined style used as a fallback in case clang-format is invoked with -style=file, " +
      "but can not find the .clang-format file to use.\nUse -fallback-style=none to skip formatting.";

    public string FormatOnSave { get; } = "Enable running clang-format when modified files are saved. Will only format if Style is found (ignores Fallback Style).";

    public string FormatEditor { get; } = "Create a .clang-format file from scratch or configure a predefined one. Detect the best matching format style for your code.";

    public string PowerShellScripts { get; } = "Manually update the PowerShell scripts used for running Clang commands.";
    public string AliasPowerShellScripts { get; } = "Manually add cpt alias in Windows PowerShell used for running Clang commands.";

    #endregion

  }
}
