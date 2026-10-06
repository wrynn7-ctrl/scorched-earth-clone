// `bug(title, fn)` is a pending test (it.skip) that documents a known bug. Run with QA_RUN_BUGS=1 to execute them all and
// see that each one still fails; when a bug is fixed its test passes and the `bug(` can become `it(`.
export const bug: Mocha.TestFunction = (process.env.QA_RUN_BUGS === '1' ? it : it.skip) as Mocha.TestFunction;
