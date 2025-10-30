from huggingface_sb3 import load_from_hub, package_to_hub
from huggingface_hub import (
    notebook_login,
)  # To log to our Hugging Face account to be able to upload models to the Hub.

from stable_baselines3 import PPO, A2C
from stable_baselines3.common.env_util import make_vec_env
from stable_baselines3.common.evaluation import evaluate_policy
from stable_baselines3.common.monitor import Monitor
from gymnasium.wrappers import RecordEpisodeStatistics, RecordVideo
import gymnasium as gym
from time import sleep
from stable_baselines3.common.vec_env import VecVideoRecorder, DummyVecEnv
from stable_baselines3.common.vec_env import VecVideoRecorder, DummyVecEnv


class RewardShapingWrapper(gym.Wrapper):
    def __init__(self, env):
        super().__init__(env)

    def step(self, action):
        observation, reward, terminated, truncated, info = self.env.step(
            action
        )
        # Modify the reward here
        reward = reward * 2  # Example: scale the reward
        return observation, reward, terminated, truncated, info


def record_video(
    env_id, model, video_length=500, prefix="", video_folder="videos/"
):
    """
    :param env_id: (str)
    :param model: (RL model)
    :param video_length: (int)
    :param prefix: (str)
    :param video_folder: (str)
    """
    eval_env = DummyVecEnv([lambda: gym.make(env_id, render_mode="rgb_array")])
    # Start the video at step=0 and record 500 steps
    eval_env = VecVideoRecorder(
        eval_env,
        video_folder=video_folder,
        record_video_trigger=lambda step: step == 0,
        video_length=video_length,
        name_prefix=prefix,
    )

    obs = eval_env.reset()
    for _ in range(video_length):
        action, _ = model.predict(obs)
        obs, _, _, _ = eval_env.step(action)

    # Close the video recorder
    eval_env.close()


num_eval_episodes = 1000
env_name = "LunarLander-v3"  # "CartPole-v1"
tensorboard_log_dir = "./tensorboard_logs"

"""
# First, we create our environment called LunarLander-v3
env = gym.make(env_name, render_mode="rgb_array")
env = RecordVideo(env, video_folder="./videos/LunarLander-v3-agent", name_prefix="eval",
                  episode_trigger=lambda x: True)
env = RecordEpisodeStatistics(env, buffer_length=num_eval_episodes)

# Then we reset this environment
observation, info = env.reset()

for _ in range(200):
  #env.render()
  #PIL.Image.fromarray(env.render())
  # Take a random action
  action = env.action_space.sample()
  print("Action taken:", action)

  # Do this action in the environment and get
  # next_state, reward, terminated, truncated and info
  observation, reward, terminated, truncated, info = env.step(action)

  # If the game is terminated (in our case we land, crashed) or truncated (timeout)
  if terminated or truncated:
      # Reset the environment
      print("Environment is reset")
      observation, info = env.reset()

env.close()

"""

# Create the environment
env = make_vec_env(env_name, n_envs=1, monitor_dir="monitor_dir")
algorithm = "ppo"  # Choose between "ppo" and "a2c"
if algorithm == "ppo":
    model = PPO(
        policy="MlpPolicy",
        env=env,
        n_steps=2048,
        # batch_size = 2048,
        n_epochs=4,
        gamma=0.999,
        gae_lambda=0.98,
        ent_coef=0.01,
        stats_window_size=100,
        tensorboard_log=tensorboard_log_dir,
        verbose=1,
    )
    total_timesteps = 1000000
elif algorithm == "a2c":
    model = A2C(
        "MlpPolicy",
        env,
        n_steps=2048,
        gamma=0.999,
        gae_lambda=0.98,
        ent_coef=0.3,
        vf_coef=0.5,
        learning_rate=0.0006,
        stats_window_size=1,
        tensorboard_log=tensorboard_log_dir,
        verbose=1,
    )
    total_timesteps = 4000000


# SOLUTION
# Train it for 1,000,000 timesteps
model.learn(total_timesteps=total_timesteps)
# Save the model
model_name = f"{algorithm}-{env_name}"
model.save(model_name)
env.close()

env_name = "LunarLander-v3"  # "CartPole-v1"
eval_env = gym.make(env_name, render_mode="rgb_array")
eval_env = RecordVideo(
    eval_env,
    video_folder=f"./videos/{env_name}-agent-post-train",
    name_prefix=f"{algorithm}",
    episode_trigger=lambda x: True,
)
eval_env = RecordEpisodeStatistics(eval_env, buffer_length=num_eval_episodes)
# eval_env = Monitor(gym.make(env_name, render_mode='rgb_array'), filename="monitor_dir/eval")
eval_env = Monitor(eval_env, filename="monitor_dir/eval")
mean_reward, std_reward = evaluate_policy(
    model, eval_env, n_eval_episodes=10, deterministic=True
)
print(f"mean_reward={mean_reward:.2f} +/- {std_reward}")

record_video(
    env_name, model, video_length=1000, prefix=f"{algorithm}-{env_name}"
)

eval_env.close()
