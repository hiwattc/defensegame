using UnityEngine;
using System.Collections;

public class Enemy : MonoBehaviour
{
    [Header("기본 설정")]
    public float speed = 10f;
    public int health = 100;
    public int goldValue = 10;
    public int damage = 1;

    [Header("현재 상태")]
    private Transform target;
    private int waypointIndex = 0;
    private bool isDead = false;

    private void Start()
    {
        target = Waypoints.points[0];
    }

    private void Update()
    {
        if (isDead)
            return;

        Vector3 dir = target.position - transform.position;
        transform.Translate(dir.normalized * speed * Time.deltaTime, Space.World);

        if (Vector3.Distance(transform.position, target.position) <= 0.4f)
        {
            GetNextWaypoint();
        }
    }

    private void GetNextWaypoint()
    {
        if (waypointIndex >= Waypoints.points.Length - 1)
        {
            ReachEnd();
            return;
        }

        waypointIndex++;
        target = Waypoints.points[waypointIndex];
    }

    public void TakeDamage(int amount)
    {
        health -= amount;

        if (health <= 0 && !isDead)
        {
            Die();
        }
    }

    private void Die()
    {
        isDead = true;
        GameManager.Instance.AddGold(goldValue);
        Destroy(gameObject);
    }

    private void ReachEnd()
    {
        GameManager.Instance.TakeDamage(damage);
        Destroy(gameObject);
    }
} 