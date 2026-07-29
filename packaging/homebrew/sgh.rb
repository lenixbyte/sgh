# Template for the Homebrew tap at lenixbyte/homebrew-tap.
# The release workflow fills in @URL@ and @SHA@ and pushes the result.
class Sgh < Formula
  desc "Per-terminal GitHub account switching for the gh CLI"
  homepage "https://github.com/lenixbyte/sgh"
  url "@URL@"
  sha256 "@SHA@"
  license "MIT"

  depends_on "gh"

  def install
    bin.install "bin/sgh"
    bash_completion.install "completions/sgh.bash" => "sgh"
    zsh_completion.install "completions/sgh.zsh" => "_sgh"
    fish_completion.install "completions/sgh.fish"
    doc.install "README.md", "CHANGELOG.md", "docs"
  end

  def caveats
    <<~EOS
      sgh switch has to change the environment of the shell you are typing in,
      so add the hook to your shell startup file:

        zsh   eval "$(sgh init zsh)"
        bash  eval "$(sgh init bash)"
        fish  sgh init fish | source

      Every other command works without it.
    EOS
  end

  test do
    assert_match "sgh #{version}", shell_output("#{bin}/sgh version")
    assert_match "command sgh", shell_output("#{bin}/sgh init bash")
    assert_match "compdef", shell_output("#{bin}/sgh completions zsh")
  end
end
