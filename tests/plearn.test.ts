import { beforeEach, describe, expect, it } from "vitest";
import { Cl, cvToValue } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const admin = accounts.get("wallet_1")!;
const user1 = accounts.get("wallet_2")!;

const ERR = {
  NOT_AUTHORIZED: Cl.uint(401),
  ALREADY_SUBMITTED: Cl.uint(403),
  QUIZ_NOT_FOUND: Cl.uint(404),
  ALREADY_VERIFIED: Cl.uint(410),
  NO_SUBMISSION: Cl.uint(412),
  INSUFFICIENT_BALANCE: Cl.uint(413),
  INVALID_REWARD: Cl.uint(414),
  INVALID_TITLE: Cl.uint(415),
  NOT_VERIFIED_OR_CLAIMED: Cl.uint(421),
  ADMIN_ALREADY_EXISTS: Cl.uint(422),
  CANNOT_REMOVE_SELF: Cl.uint(423),
  INVALID_QUIZ_ID: Cl.uint(424),
  ALREADY_INITIALIZED: Cl.uint(425),
  LIST_FULL: Cl.uint(426),
  INVALID_HASH: Cl.uint(427),
  TRANSFER_FAILED: Cl.uint(428),
  ESCROW_UNFUNDED: Cl.uint(429),
};

const DEFAULT_TITLE = "Proof-of-Learning Quiz";
const CORRECT_HASH = Cl.bufferFromHex("11".repeat(32));
const WRONG_HASH = Cl.bufferFromHex("22".repeat(32));
const DEFAULT_REWARD = 2_000_000n; // 2 STX (in microstacks)
const FUNDING_AMOUNT = 8_000_000n; // 8 STX

const addQuizArgs = (
  title = DEFAULT_TITLE,
  hash = CORRECT_HASH,
  reward: bigint | number = DEFAULT_REWARD,
  autoVerify = true,
) => [Cl.stringAscii(title), hash, Cl.uint(reward), Cl.bool(autoVerify)];

const initializeContract = (sender = deployer) =>
  simnet.callPublicFn("plearn", "initialize", [], sender);

const fundContract = (amount = FUNDING_AMOUNT, sender = deployer) =>
  simnet.callPublicFn("plearn", "fund-contract", [Cl.uint(amount)], sender);

const addQuiz = (
  title = DEFAULT_TITLE,
  reward: bigint | number = DEFAULT_REWARD,
  autoVerify = true,
  sender = deployer,
  hash = CORRECT_HASH,
) => simnet.callPublicFn("plearn", "add-quiz", addQuizArgs(title, hash, reward, autoVerify), sender);

const submitAnswer = (quizId: number, answer = CORRECT_HASH, sender = user1) =>
  simnet.callPublicFn("plearn", "submit-answer", [Cl.uint(quizId), answer], sender);

const verifyAnswer = (quizId: number, target: string, sender = deployer) =>
  simnet.callPublicFn("plearn", "verify-answer", [Cl.uint(quizId), Cl.principal(target)], sender);

const claimReward = (quizId: number, sender = user1) =>
  simnet.callPublicFn("plearn", "claim-reward", [Cl.uint(quizId)], sender);

const deactivateQuiz = (quizId: number, sender = deployer) =>
  simnet.callPublicFn("plearn", "deactivate-quiz", [Cl.uint(quizId)], sender);

describe("plearn::initialize and admin controls", () => {
  it("only owner can initialize and it can be done once", () => {
    const first = initializeContract(admin);
    expect(first.result).toBeErr(ERR.NOT_AUTHORIZED);

    const second = initializeContract();
    expect(second.result).toBeOk(Cl.bool(true));

    const third = initializeContract();
    expect(third.result).toBeErr(ERR.ALREADY_INITIALIZED);
  });

  describe("admin management", () => {
    beforeEach(() => {
      const init = initializeContract();
      expect(init.result).toBeOk(Cl.bool(true));
    });

    it("adds admins and prevents duplicates or non-admin actions", () => {
      const add = simnet.callPublicFn("plearn", "add-admin", [Cl.principal(admin)], deployer);
      expect(add.result).toBeOk(Cl.bool(true));

      const duplicate = simnet.callPublicFn("plearn", "add-admin", [Cl.principal(admin)], deployer);
      expect(duplicate.result).toBeErr(ERR.ADMIN_ALREADY_EXISTS);

      const nonAdminAdd = simnet.callPublicFn(
        "plearn",
        "add-admin",
        [Cl.principal(user1)],
        user1,
      );
      expect(nonAdminAdd.result).toBeErr(ERR.NOT_AUTHORIZED);

      const isAdmin = simnet.callReadOnlyFn("plearn", "is-user-admin", [Cl.principal(admin)], admin);
      expect(isAdmin.result).toBeBool(true);
    });

    it("blocks self-removal and unauthorized removals", () => {
      const add = simnet.callPublicFn("plearn", "add-admin", [Cl.principal(admin)], deployer);
      expect(add.result).toBeOk(Cl.bool(true));

      const selfRemove = simnet.callPublicFn("plearn", "remove-admin", [Cl.principal(deployer)], deployer);
      expect(selfRemove.result).toBeErr(ERR.CANNOT_REMOVE_SELF);

      const nonAdminRemove = simnet.callPublicFn(
        "plearn",
        "remove-admin",
        [Cl.principal(admin)],
        user1,
      );
      expect(nonAdminRemove.result).toBeErr(ERR.NOT_AUTHORIZED);

      const remove = simnet.callPublicFn("plearn", "remove-admin", [Cl.principal(admin)], deployer);
      expect(remove.result).toBeOk(Cl.bool(true));
    });
  });
});

describe("plearn::funding and quiz lifecycle", () => {
  beforeEach(() => {
    const init = initializeContract();
    expect(init.result).toBeOk(Cl.bool(true));
  });

  it("rejects quiz creation when insufficient available balance", () => {
    const quiz = addQuiz(DEFAULT_TITLE, DEFAULT_REWARD, true, deployer);
    expect(quiz.result).toBeErr(ERR.INSUFFICIENT_BALANCE);
  });

  it("funds the contract and creates a quiz with escrow", () => {
    const fund = fundContract();
    expect(fund.result).toBeOk(Cl.bool(true));

    const quiz = addQuiz();
    expect(quiz.result).toBeOk(Cl.uint(1));

    const reserved = simnet.callReadOnlyFn("plearn", "get-reserved-contract-balance", [], deployer);
    expect(reserved.result).toBeUint(DEFAULT_REWARD);

    const nextId = simnet.callReadOnlyFn("plearn", "get-next-quiz-id", [], deployer);
    expect(nextId.result).toBeUint(2);

    const stored = simnet.callReadOnlyFn("plearn", "get-quiz", [Cl.uint(1)], deployer);
    expect(stored.result).toBeOk(expect.anything());
    const storedValue = cvToValue(stored.result);
    expect(storedValue.value.title.value).toBe(DEFAULT_TITLE);
    expect(Number(storedValue.value.reward.value)).toBe(Number(DEFAULT_REWARD));
    expect(Number(storedValue.value.escrowed.value)).toBe(Number(DEFAULT_REWARD));
    expect(storedValue.value.creator.value).toBe(deployer);
    expect(storedValue.value.active.value).toBe(true);
    expect(storedValue.value["verified-users"].value).toEqual([]);
  });

  it("handles auto-verify submissions and stats updates", () => {
    expect(fundContract().result).toBeOk(Cl.bool(true));
    expect(addQuiz().result).toBeOk(Cl.uint(1));

    const submission = submitAnswer(1, CORRECT_HASH, user1);
    expect(submission.result).toBeOk(Cl.bool(true));

    const status = simnet.callReadOnlyFn(
      "plearn",
      "get-user-status",
      [Cl.uint(1), Cl.principal(user1)],
      user1,
    );
    expect(status.result).toBeOk(expect.anything());
    const statusValue = cvToValue(status.result);
    const answerHashCv = statusValue.value["answer-hash"];
    expect(answerHashCv.value).toBe(`0x${CORRECT_HASH.value}`);
    expect(statusValue.value.verified.value).toBe(true);
    expect(statusValue.value.claimed.value).toBe(false);

    const verifiedList = simnet.callReadOnlyFn("plearn", "get-verified-users", [Cl.uint(1)], user1);
    expect(verifiedList.result).toBeOk(Cl.list([Cl.principal(user1)]));

    const stats = simnet.callReadOnlyFn("plearn", "get-quiz-stats", [Cl.uint(1)], deployer);
    expect(stats.result).toBeOk(
      Cl.tuple({
        "total-submissions": Cl.uint(1),
        "total-verified": Cl.uint(1),
        "total-claimed": Cl.uint(0),
      }),
    );
  });

  it("prevents duplicate submissions and allows manual verification", () => {
    expect(fundContract().result).toBeOk(Cl.bool(true));
    expect(addQuiz(DEFAULT_TITLE, DEFAULT_REWARD, false).result).toBeOk(Cl.uint(1));

    const first = submitAnswer(1, WRONG_HASH, user1);
    expect(first.result).toBeOk(Cl.bool(true));

    const duplicate = submitAnswer(1, CORRECT_HASH, user1);
    expect(duplicate.result).toBeErr(ERR.ALREADY_SUBMITTED);

    const verify = verifyAnswer(1, user1, deployer);
    expect(verify.result).toBeOk(Cl.bool(true));

    const verifyTwice = verifyAnswer(1, user1, deployer);
    expect(verifyTwice.result).toBeErr(ERR.ALREADY_VERIFIED);
  });

  it("allows verified users to claim rewards and updates balances", () => {
    expect(fundContract().result).toBeOk(Cl.bool(true));
    expect(addQuiz(DEFAULT_TITLE, DEFAULT_REWARD, true).result).toBeOk(Cl.uint(1));
    expect(submitAnswer(1, CORRECT_HASH, user1).result).toBeOk(Cl.bool(true));

    const claim = claimReward(1, user1);
    expect(claim.result).toBeOk(Cl.uint(DEFAULT_REWARD));

    const status = simnet.callReadOnlyFn(
      "plearn",
      "get-user-status",
      [Cl.uint(1), Cl.principal(user1)],
      user1,
    );
    expect(status.result).toBeOk(expect.anything());
    const statusValue = cvToValue(status.result);
    expect(statusValue.value.claimed.value).toBe(true);
    expect(statusValue.value.verified.value).toBe(true);

    const reserved = simnet.callReadOnlyFn("plearn", "get-reserved-contract-balance", [], deployer);
    expect(reserved.result).toBeUint(0);

    const tracked = simnet.callReadOnlyFn("plearn", "get-tracked-contract-balance", [], deployer);
    expect(tracked.result).toBeUint(FUNDING_AMOUNT - DEFAULT_REWARD);

    const quiz = simnet.callReadOnlyFn("plearn", "get-quiz", [Cl.uint(1)], deployer);
    expect(quiz.result).toBeOk(expect.anything());
    const quizValue = cvToValue(quiz.result);
    expect(quizValue.value.active.value).toBe(false);
    expect(Number(quizValue.value.escrowed.value)).toBe(0);

    const stats = simnet.callReadOnlyFn("plearn", "get-quiz-stats", [Cl.uint(1)], deployer);
    expect(stats.result).toBeOk(
      Cl.tuple({
        "total-submissions": Cl.uint(1),
        "total-verified": Cl.uint(1),
        "total-claimed": Cl.uint(1),
      }),
    );
  });

  it("refunds unused escrow on deactivation", () => {
    expect(fundContract().result).toBeOk(Cl.bool(true));
    expect(addQuiz(DEFAULT_TITLE, 5_000_000n, false).result).toBeOk(Cl.uint(1));

    const deactivate = deactivateQuiz(1, deployer);
    expect(deactivate.result).toBeOk(Cl.bool(true));

    const quiz = simnet.callReadOnlyFn("plearn", "get-quiz", [Cl.uint(1)], deployer);
    expect(quiz.result).toBeOk(expect.anything());
    const quizValue = cvToValue(quiz.result);
    expect(quizValue.value.active.value).toBe(false);
    expect(Number(quizValue.value.escrowed.value)).toBe(0);

    const reserved = simnet.callReadOnlyFn("plearn", "get-reserved-contract-balance", [], deployer);
    expect(reserved.result).toBeUint(0);

    const tracked = simnet.callReadOnlyFn("plearn", "get-tracked-contract-balance", [], deployer);
    expect(tracked.result).toBeUint(FUNDING_AMOUNT - 5_000_000n);
  });
});
