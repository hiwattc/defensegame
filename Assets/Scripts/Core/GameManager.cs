using UnityEngine;
using System.Collections.Generic;

public class GameManager : MonoBehaviour
{
    public static GameManager Instance { get; private set; }

    [Header("게임 설정")]
    public int startingGold = 100;
    public int startingLives = 20;
    public float waveDelay = 30f;

    [Header("현재 게임 상태")]
    public int currentGold;
    public int currentLives;
    public int currentWave;
    public bool isGameOver;

    private void Awake()
    {
        if (Instance == null)
        {
            Instance = this;
            DontDestroyOnLoad(gameObject);
        }
        else
        {
            Destroy(gameObject);
        }
    }

    private void Start()
    {
        InitializeGame();
    }

    private void InitializeGame()
    {
        currentGold = startingGold;
        currentLives = startingLives;
        currentWave = 0;
        isGameOver = false;
    }

    public void AddGold(int amount)
    {
        currentGold += amount;
        // UI 업데이트 이벤트 발생
    }

    public bool SpendGold(int amount)
    {
        if (currentGold >= amount)
        {
            currentGold -= amount;
            // UI 업데이트 이벤트 발생
            return true;
        }
        return false;
    }

    public void TakeDamage(int damage)
    {
        currentLives -= damage;
        if (currentLives <= 0)
        {
            GameOver();
        }
        // UI 업데이트 이벤트 발생
    }

    private void GameOver()
    {
        isGameOver = true;
        // 게임 오버 UI 표시
    }

    public void StartNextWave()
    {
        currentWave++;
        // 웨이브 매니저에 다음 웨이브 시작 신호 전달
    }
} 