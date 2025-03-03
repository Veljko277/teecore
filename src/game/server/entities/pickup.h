

#ifndef GAME_SERVER_ENTITIES_PICKUP_H
#define GAME_SERVER_ENTITIES_PICKUP_H

#include <game/server/entity.h>

const int PickupPhysSize = 14;

class CPickup : public CAnimatedEntity
{
public:
	CPickup(CGameWorld *pGameWorld, int Type, int SubType, vec2 Pivot, vec2 RelPos, int PosEnv);

	virtual void Reset();
	virtual void Tick();
	virtual void TickPaused();
	virtual void Snap(int SnappingClient);

private:
	int m_Type;
	int m_Subtype;
	int m_SpawnTick;
};

#endif
