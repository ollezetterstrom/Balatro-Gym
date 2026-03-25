"""
train.py — Train a PPO agent on Balatro.

Usage:
    python train.py                     # default: 100K steps
    python train.py --steps 1000000     # 1M steps
    python train.py --eval              # evaluate trained model

Requires: pip install -r requirements.txt stable-baselines3

Before training, verify correctness:
    lua validate.lua                    # 49/49 tests must pass
"""

import argparse
import os
import sys
import time

import numpy as np


def check_prerequisites():
    """Verify Lua validation passes before training."""
    import subprocess
    import shutil

    lua_cmd = shutil.which("lua") or shutil.which("lua5.4") or shutil.which("luajit")
    if not lua_cmd:
        print("WARNING: lua not found in PATH. Skipping validation.")
        return

    result = subprocess.run(
        [lua_cmd, "validate.lua"],
        capture_output=True, text=True, cwd=os.path.dirname(__file__) or "."
    )
    if result.returncode != 0:
        print("VALIDATION FAILED. Fix scoring before training.")
        print(result.stdout)
        sys.exit(1)
    passed = result.stdout.count("[OK]")
    print(f"Validation: {passed}/49 passed. Engine is correct.\n")


def train(steps=100000, seed=42, log_dir="logs/"):
    """Train a PPO agent."""
    try:
        from stable_baselines3 import PPO
    except ImportError:
        print("Install stable-baselines3: pip install stable-baselines3")
        sys.exit(1)

    import balatro_gym_simple
    env = balatro_gym_simple.BalatroSimpleEnv()

    model = PPO(
        "MlpPolicy",
        env,
        verbose=1,
        learning_rate=3e-4,
        n_steps=2048,
        batch_size=64,
        n_epochs=10,
        gamma=0.99,
        seed=seed,
    )

    print(f"Training PPO for {steps} steps...")
    t0 = time.time()
    model.learn(total_timesteps=steps)
    elapsed = time.time() - t0

    # Save model
    os.makedirs(log_dir, exist_ok=True)
    model_path = os.path.join(log_dir, "balatro_ppo")
    model.save(model_path)
    print(f"\nTraining complete in {elapsed:.1f}s")
    print(f"Model saved to {model_path}.zip")

    env.close()
    return model


def evaluate(model_path=None, n_episodes=20):
    """Evaluate a trained model (or random agent)."""
    import balatro_gym_simple

    env = balatro_gym_simple.BalatroSimpleEnv()

    if model_path and os.path.exists(model_path + ".zip"):
        from stable_baselines3 import PPO
        model = PPO.load(model_path)
        agent_name = "PPO"
    else:
        model = None
        agent_name = "Random"

    rewards = []
    antes_reached = []
    max_chips = []

    for ep in range(n_episodes):
        obs, info = env.reset(seed=42 + ep)
        ep_reward = 0
        done = False
        steps_in_ep = 0

        while not done:
            if model:
                action, _ = model.predict(obs, deterministic=True)
            else:
                action = env.action_space.sample()

            obs, reward, done, trunc, info = env.step(action)
            ep_reward += reward
            steps_in_ep += 1
            if done or trunc or steps_in_ep > 200:
                break

        rewards.append(ep_reward)
        antes_reached.append(info.get("ante", 1))
        max_chips.append(info.get("chips", 0))

    print(f"\n=== {agent_name} Evaluation ({n_episodes} episodes) ===")
    print(f"  Reward:  mean={np.mean(rewards):.2f}  std={np.std(rewards):.2f}  "
          f"min={np.min(rewards):.2f}  max={np.max(rewards):.2f}")
    print(f"  Ante:    mean={np.mean(antes_reached):.1f}  "
          f"max={np.max(antes_reached):.0f}")
    print(f"  Chips:   mean={np.mean(max_chips):.0f}  "
          f"max={np.max(max_chips):.0f}")

    env.close()
    return rewards


def compare():
    """Compare random vs trained agent."""
    print("--- Random Agent ---")
    random_rewards = evaluate(model_path=None, n_episodes=5)

    model_path = "logs/balatro_ppo"
    if os.path.exists(model_path + ".zip"):
        print("\n--- Trained Agent ---")
        trained_rewards = evaluate(model_path=model_path, n_episodes=5)

        improvement = np.mean(trained_rewards) - np.mean(random_rewards)
        print(f"\nImprovement: {improvement:+.2f} reward over random")
        if improvement > 0:
            print("Agent is BETTER than random!")
        else:
            print("Agent is NOT better than random. Train longer or adjust hyperparameters.")
    else:
        print(f"\nNo trained model found at {model_path}.zip")
        print("Run: python train.py --steps 100000")


def main():
    parser = argparse.ArgumentParser(description="Balatro RL training")
    parser.add_argument("--steps", type=int, default=100000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--eval", action="store_true", help="Evaluate only")
    parser.add_argument("--compare", action="store_true", help="Compare random vs trained")
    parser.add_argument("--no-check", action="store_true", help="Skip validation check")
    args = parser.parse_args()

    if not args.no_check:
        check_prerequisites()

    if args.eval:
        evaluate(model_path="logs/balatro_ppo", n_episodes=50)
    elif args.compare:
        compare()
    else:
        train(steps=args.steps, seed=args.seed)


if __name__ == "__main__":
    main()
